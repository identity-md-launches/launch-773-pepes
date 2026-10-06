// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Pepes} from "../src/Pepes.sol";

/// @dev A closed group of holders allows conservation checks after arbitrary action sequences.
contract PepesHandler is Test {
    Pepes public immutable token;
    address[4] public holders = [address(0xA11CE), address(0xB0B), address(0xCA401), address(0xD00D)];
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Pepes token_) {
        token = token_;
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = holders[fromSeed % holders.length];
        address to = holders[toSeed % holders.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = holders[ownerSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = holders[ownerSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        address to = holders[toSeed % holders.length];
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 balance = token.balanceOf(owner);
        amount = bound(amount, 0, balance < allowance ? balance : allowance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (allowance != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }
}

contract PepesInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Pepes private token;
    PepesHandler private handler;

    function setUp() public {
        token = new Pepes();
        handler = new PepesHandler(token);
        for (uint256 i; i < 4; ++i) {
            token.transfer(handler.holders(i), SUPPLY / 4);
        }

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = PepesHandler.move.selector;
        selectors[1] = PepesHandler.approve.selector;
        selectors[2] = PepesHandler.spend.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyAndBalancesAreConserved() public view {
        uint256 held;
        for (uint256 i; i < 4; ++i) {
            held += token.balanceOf(handler.holders(i));
        }
        assertEq(held, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_allowancesMatchApprovalsAndSpending() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.holders(i);
                address spender = handler.holders(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
