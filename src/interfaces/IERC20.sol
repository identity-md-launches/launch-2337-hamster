// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title ERC-20 interface with the optional metadata extension (EIP-20).
interface IERC20 {
    /// @notice Emitted when `value` tokens move from `from` to `to`. A mint has `from == address(0)`.
    event Transfer(address indexed from, address indexed to, uint256 value);
    /// @notice Emitted when `owner` sets the allowance of `spender` to `value`.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice The token's name.
    function name() external view returns (string memory);
    /// @notice The token's symbol.
    function symbol() external view returns (string memory);
    /// @notice The number of decimals the token uses.
    function decimals() external view returns (uint8);
    /// @notice The amount of tokens in existence.
    function totalSupply() external view returns (uint256);
    /// @notice The amount of tokens owned by `account`.
    function balanceOf(address account) external view returns (uint256);
    /// @notice The remaining amount `spender` may spend on behalf of `owner`.
    function allowance(address owner, address spender) external view returns (uint256);
    /// @notice Moves `amount` tokens from the caller to `to`. Returns true on success.
    function transfer(address to, uint256 amount) external returns (bool);
    /// @notice Sets `spender`'s allowance over the caller's tokens to `amount`. Returns true on success.
    function approve(address spender, uint256 amount) external returns (bool);
    /// @notice Moves `amount` tokens from `from` to `to` using the caller's allowance. Returns true on success.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
