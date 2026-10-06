// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pepes} from "../src/Pepes.sol";

/// @dev A closed group of holders allows conservation checks after arbitrary action sequences.
contract PepesHandler is Test {
    Pepes public immutable token;
    address[4] public holders = [address(0xA11CE), address(0xB0B), address(0xCA401), address(0xD00D)];
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    mapping(address => uint256) public expectedBalance;

    constructor(Pepes token_, uint256 initialPerHolder) {
        token = token_;
        // Seed from the fixture, never from the balances reported by the token.
        for (uint256 i; i < holders.length; ++i) {
            expectedBalance[holders[i]] = initialPerHolder;
        }
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = holders[fromSeed % holders.length];
        address to = holders[toSeed % holders.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordMove(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = holders[ownerSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        // Exercise revocation and infinite approval frequently, as well as raw uint256 values.
        uint256 mode = amount % 4;
        if (mode == 0) amount = 0;
        else if (mode == 1) amount = type(uint256).max;
        else if (mode == 2) amount = bound(amount, 0, 1_000_000_000 ether);
        _approve(owner, spender, amount);
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = holders[ownerSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        address to = holders[toSeed % holders.length];
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, 0, balance < allowance ? balance : allowance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _recordMove(owner, to, amount);
        if (allowance != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }

    function rejectOverspend(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = holders[fromSeed % holders.length];
        address to = holders[toSeed % holders.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
        // No ghost update: every rejected action must leave the entire ledger unchanged.
    }

    function rejectAllowanceOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 approved) external {
        address owner = holders[ownerSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        approved = bound(approved, 0, expectedBalance[owner]);
        _approve(owner, spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, spender, approved + 1);
    }

    function rejectUnfundedSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 excess, bool infinite) external {
        address owner = holders[ownerSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - 1 - balance);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, spender, amount);
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = holders[ownerSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }

    function revokeAndRejectSpend(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = holders[ownerSeed % holders.length];
        address spender = holders[spenderSeed % holders.length];
        _approve(owner, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, spender, 1);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _recordMove(address from, address to, uint256 amount) private {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract PepesInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Pepes private token;
    PepesHandler private handler;

    function setUp() public {
        token = new Pepes();
        handler = new PepesHandler(token, SUPPLY / 4);
        for (uint256 i; i < 4; ++i) {
            assertTrue(token.transfer(handler.holders(i), SUPPLY / 4));
            assertEq(token.balanceOf(handler.holders(i)), SUPPLY / 4);
        }

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = PepesHandler.move.selector;
        selectors[1] = PepesHandler.approve.selector;
        selectors[2] = PepesHandler.spend.selector;
        selectors[3] = PepesHandler.rejectOverspend.selector;
        selectors[4] = PepesHandler.rejectAllowanceOverspend.selector;
        selectors[5] = PepesHandler.rejectUnfundedSpend.selector;
        selectors[6] = PepesHandler.rejectZeroRecipient.selector;
        selectors[7] = PepesHandler.revokeAndRejectSpend.selector;
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
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_eachHolderKeepsExactlyTheirTokens() public view {
        // Conservation alone would miss a transfer crediting the wrong holder.
        for (uint256 i; i < 4; ++i) {
            address holder = handler.holders(i);
            assertEq(token.balanceOf(holder), handler.expectedBalance(holder));
        }
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
