# HAMSTER (HAMSTER)

A fixed-supply ERC-20 for an IdentityMD custom token launch on Ethereum.

| Item | Value |
| --- | --- |
| Solidity contract | `HamsterToken` (`src/HamsterToken.sol`) |
| `name()` | `HAMSTER` |
| `symbol()` | `HAMSTER` |
| `decimals()` | `18` |
| `totalSupply()` | `1_000_000_000 * 10^18` = `1000000000000000000000000000` minor units |
| Constructor arguments | none |
| Minted to | `msg.sender` of the constructor, once, in the constructor |
| Owner / admin | none |
| Compiler | solc `0.8.26`, optimizer on (200 runs), `evm_version = "cancun"`, `bytecode_hash = "none"` |

## What the token does

- Implements EIP-20 with the optional metadata functions and the standard `Transfer` and
  `Approval` events. The interface it implements is `src/interfaces/IERC20.sol`.
- Mints the whole supply to the deployer in the constructor and emits
  `Transfer(address(0), deployer, TOTAL_SUPPLY)`. `INITIAL_HOLDER` records who that was.
- Has no `mint`, `burn`, `burnFrom`, `pause`, blocklist, freeze, seize, fee, tax, reflection,
  owner, upgrade hook, `receive` or `fallback`. Unknown calldata and ether both revert.
- `totalSupply()` is a compile-time constant. It cannot grow or shrink after deployment.
- Transfers and approvals are plain: what is sent is what arrives, with no exemption list
  because nothing needs exempting. The launch flows (factory to distributor, distributor to
  claimant, seed into the Uniswap v4 PoolManager, buy and sell) move exactly the stated amounts.
- `transfer` and `transferFrom` to the zero address revert (`InvalidRecipient`), so no balance
  can be destroyed by mistake. `approve` with the zero address as spender reverts (`InvalidSpender`).
- An allowance of `type(uint256).max` is unlimited and is not decremented by `transferFrom`.
  Any other allowance is reduced by the amount spent, and an `Approval` event reports the remainder.
- Failures use custom errors: `InsufficientBalance(from, balance, needed)` and
  `InsufficientAllowance(owner, spender, allowance, needed)`.
- The contract imports no library, so the attested bytecode is exactly this source. Its runtime
  contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT` (a test scans for them).

## Assumptions

- The brief asks for a plain token: name, symbol and supply only. No transfer rule, tax, burn,
  vesting or governance was requested, so none was added.
- "All minted once to the deployer" is read as `msg.sender` of the constructor. On the IdentityMD
  launch that is the ProjectFactory, which then distributes the supply as described below. On a
  local deployment it is whichever account runs the deploy script.
- The classic `approve` race (a spender using both an old and a new allowance) is inherent to
  EIP-20. Holders changing a non-zero allowance should set it to zero first or approve only what the
  spender needs. The token does not add `increaseAllowance`/`decreaseAllowance`; they are not part
  of EIP-20 and OpenZeppelin v5 dropped them too.

## Deployment parameters

The token takes no constructor arguments. There is nothing to configure before or after launch.

The launch itself is IdentityMD's: its verifier attests the built bytecode and its deployer calls
`ProjectFactory.launchCustom`. The manifest (`launch.json`) is written by the manifest step after
this work is accepted, not by this repository. The values that step is told, recorded here for the
reader:

| Launch setting | Value |
| --- | --- |
| Chain | Ethereum, chain id 1 |
| `token.contract` | `HamsterToken` |
| `token.totalSupply` | `1000000000000000000000000000` |
| `token.decimals` | `18` |
| `token.constructorArgs` | `[]` |
| Application contracts | none |
| Paired currency | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` |
| `pool.fee` | `12500` (1.25%) |
| `pool.tickSpacing` | `60` |
| `pool.initialPrice` | `79228162514264337593543950336` (provenance only; the deployer derives the real opening price) |
| `economics.poolBps` | `7000` |
| `economics.initialMarketCapWei` | `2500000000000000000000` (2,500 IMD for the whole supply) |
| `economics.remainderTo` | `0x1ee3ffadfe138415a2ddaedeebe5f46616fa413d` |

Supply flow at launch, all performed by the factory from the minted balance:

1. 10% to the launch's MerkleDistributor for the swarm (2% to contributors, 8% to paired seats).
2. 70% seeds the single-sided HAMSTER/IMD Uniswap v4 pool at the price derived from the
   2,500 IMD opening market cap.
3. The remaining 20% is forwarded to `economics.remainderTo`.

None of this is encoded in the token: it holds no allocation, reserve or exemption list.

### After launch

Nothing to set. The token has no owner and no setters.

### Local deployment (review and testing only)

`script/DeployHamsterToken.s.sol` deploys the token with `new HamsterToken()`. Its `deploy()`
function is what the tests call; `run()` wraps it in a broadcast. It reads no environment variables.

```
forge script script/DeployHamsterToken.s.sol --rpc-url <local rpc> --broadcast
```

This assignment does not deploy, sign or verify anything on a public chain.

## Operational responsibilities

- **Holders** are solely responsible for their balances. There is no recovery, freeze or clawback
  path for anyone, including the deployer. Tokens sent to a wrong (non-zero) address are lost.
- **Allowances** are the holder's to manage. Approve exact amounts to contracts you do not fully
  trust; an unlimited allowance lets the spender move everything you hold, now or later.
- **The deployer (factory)** receives the whole supply and is responsible for distributing it as the
  launch says. After that, the deployer has no special powers over the token.
- **Explorer verification** of the deployed source is the launch deployer's step, not this
  repository's. Build settings needed to reproduce the bytecode are pinned in `foundry.toml`.
- **No upgrade path** exists. A change to the token's behaviour requires a new token.

## Security notes

Checked against the eth-security reference supplied with the task:

- Access control: there are no privileged functions, so there is nothing to restrict.
- Reentrancy: the token makes no external calls.
- Input validation: zero recipient and zero spender are rejected; balance and allowance are checked
  before any state change; arithmetic that is unchecked is guarded by those checks and by the
  constant total supply.
- Events: every state change (mint, transfer, approval, allowance spend) emits one.
- No proxies, no delegatecall, no signatures, no oracles, no swaps inside the contract.
- Tools run: `forge build`, `forge test` (unit, fuzz with the verifier's seed, invariants),
  `forge fmt --check`. Slither and Mythril were not available in this environment and did not run.

Tests passing are not an audit. The launch policy's independent review still applies.

## Layout

```
foundry.toml                      compiler and profile pins
remappings.txt                    forge-std/ -> lib/forge-std/src/
src/HamsterToken.sol              the token
src/interfaces/IERC20.sol         the ERC-20 interface it implements
script/DeployHamsterToken.s.sol   local deploy script (deploy() is testable without env)
test/HamsterToken.t.sol           unit and fuzz tests
test/HamsterToken.invariant.t.sol handler-based invariants (supply constant, balances conserve)
test/DeployHamsterToken.t.sol     calls the script's deploy() directly
lib/forge-std                     forge-std v1.11.0, vendored as plain files (MIT/Apache-2.0)
```

## Running the checks

```
forge build
FOUNDRY_FUZZ_SEED=0xe1e205f219533326e49a16d133bedc60bec0e4035d2a48d75bfc0d8523ea0083 forge test
forge fmt --check
```
