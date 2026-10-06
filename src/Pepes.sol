// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Pepes (PEPES)
/// @notice Fixed-supply ERC-20 with 18 decimals and no administrative powers.
contract Pepes is ERC20 {
    /// @notice One billion whole tokens, expressed in the smallest token unit.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev The immediate deployer receives everything, including when it is a factory.
    constructor() ERC20("Pepes", "PEPES") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
