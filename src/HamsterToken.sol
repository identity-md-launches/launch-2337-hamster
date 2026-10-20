// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "./interfaces/IERC20.sol";

/// @title HAMSTER (HAMSTER)
/// @notice A fixed-supply ERC-20. The whole supply, 1,000,000,000 HAMSTER with 18 decimals, is
/// minted once to the deployer (`msg.sender`) in the constructor. There is no owner, no minter, no
/// pause, no blocklist and no tax: after deployment the token has no privileged party at all, and
/// the supply can neither grow nor shrink.
/// @dev Self-contained on purpose. It vendors no library so that the bytecode the launch attests is
/// exactly what this file says. Transfers and approvals to the zero address revert, so no balance
/// can be burned by mistake. An allowance of `type(uint256).max` is treated as unlimited and is not
/// decremented, which is the convention wallets and routers expect.
contract HamsterToken is IERC20 {
    // ----------------------------------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------------------------------

    /// @notice `transfer` or `transferFrom` to the zero address.
    error InvalidRecipient();
    /// @notice `approve` with the zero address as spender.
    error InvalidSpender();
    /// @notice The sender holds less than the amount being moved.
    error InsufficientBalance(address from, uint256 balance, uint256 needed);
    /// @notice The spender was allowed less than the amount being moved.
    error InsufficientAllowance(address owner, address spender, uint256 allowance, uint256 needed);

    // ----------------------------------------------------------------------------------------
    // Metadata and supply
    // ----------------------------------------------------------------------------------------

    /// @notice ERC-20 name.
    string public constant NAME = "HAMSTER";
    /// @notice ERC-20 symbol.
    string public constant SYMBOL = "HAMSTER";
    /// @notice ERC-20 decimals.
    uint8 public constant DECIMALS = 18;
    /// @notice The whole supply in minor units: 1,000,000,000 * 10^18. Minted once, never changed.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(DECIMALS);

    /// @notice The address the constructor minted the supply to.
    address public immutable INITIAL_HOLDER;

    // ----------------------------------------------------------------------------------------
    // Storage
    // ----------------------------------------------------------------------------------------

    mapping(address account => uint256) private _balances;
    mapping(address owner => mapping(address spender => uint256)) private _allowances;

    // ----------------------------------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------------------------------

    /// @notice Mints `TOTAL_SUPPLY` to `msg.sender`, the deployer. Takes no arguments and calls no
    /// other contract, so it deploys on an empty chain and through a factory alike.
    constructor() {
        INITIAL_HOLDER = msg.sender;
        _balances[msg.sender] = TOTAL_SUPPLY;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);
    }

    // ----------------------------------------------------------------------------------------
    // ERC-20 views
    // ----------------------------------------------------------------------------------------

    /// @inheritdoc IERC20
    function name() external pure override returns (string memory) {
        return NAME;
    }

    /// @inheritdoc IERC20
    function symbol() external pure override returns (string memory) {
        return SYMBOL;
    }

    /// @inheritdoc IERC20
    function decimals() external pure override returns (uint8) {
        return DECIMALS;
    }

    /// @inheritdoc IERC20
    /// @dev A constant: nothing in this contract mints or burns.
    function totalSupply() external pure override returns (uint256) {
        return TOTAL_SUPPLY;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    // ----------------------------------------------------------------------------------------
    // ERC-20 actions
    // ----------------------------------------------------------------------------------------

    /// @inheritdoc IERC20
    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @inheritdoc IERC20
    /// @dev Sets the allowance outright. To change a non-zero allowance safely against the classic
    /// front-running race, set it to zero first or use the amount the spender actually needs.
    function approve(address spender, uint256 amount) external override returns (bool) {
        if (spender == address(0)) revert InvalidSpender();
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    // ----------------------------------------------------------------------------------------
    // Internals
    // ----------------------------------------------------------------------------------------

    function _transfer(address from, address to, uint256 amount) private {
        if (to == address(0)) revert InvalidRecipient();
        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) revert InsufficientBalance(from, fromBalance, amount);
        unchecked {
            // fromBalance >= amount was just checked, and the sum of all balances is TOTAL_SUPPLY,
            // so the recipient's balance cannot overflow.
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) private {
        uint256 current = _allowances[owner][spender];
        if (current == type(uint256).max) return;
        if (current < amount) revert InsufficientAllowance(owner, spender, current, amount);
        unchecked {
            _allowances[owner][spender] = current - amount;
        }
        emit Approval(owner, spender, current - amount);
    }
}
