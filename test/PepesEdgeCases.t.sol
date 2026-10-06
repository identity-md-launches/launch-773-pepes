// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pepes} from "src/Pepes.sol";

/// @dev Complements the existing launch and metadata tests with arithmetic and authorization boundaries.
/// forge-config: default.fuzz.runs = 1000
contract PepesEdgeCasesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    Pepes private token;

    function setUp() public {
        token = new Pepes();
    }

    function test_oneSmallestUnitCannotBeTransferredTwice() public {
        assertTrue(token.transfer(ALICE, 1));
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_consumedAllowanceCannotBeReplayedAfterRefund() public {
        token.transfer(ALICE, 2);
        vm.prank(ALICE);
        token.approve(SPENDER, 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 1));
        vm.prank(BOB);
        assertTrue(token.transfer(ALICE, 1));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), 2);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
    }

    function test_largestFiniteAllowanceIsConsumedOnEverySpend() public {
        token.approve(SPENDER, type(uint256).max - 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 3);
        assertEq(token.balanceOf(ALICE), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_ownerUsingTransferFromNeedsSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_selfTransfersStillRequireEnoughBalanceAtMaximumAmount() public {
        bytes memory failure = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
        );
        vm.expectRevert(failure);
        token.transfer(address(this), type(uint256).max);
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(failure);
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(this), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroDelegatedTransferEmitsEventAndKeepsAllowance() public {
        token.approve(SPENDER, 1);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 0));
        assertEq(token.allowance(address(this), SPENDER), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_zeroApprovalStillRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroDelegatedTransferStillRejectsZeroReceiver() public {
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroSenderCannotUseTransferFromEvenForZeroAmount() public {
        // The rejection may originate in approval validation or transfer validation.
        vm.expectRevert();
        vm.prank(SPENDER);
        token.transferFrom(address(0), ALICE, 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(0), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferRoundTripRestoresEveryBalance(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(ALICE, amount));
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        vm.prank(BOB);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_allowanceOverspendRevertsDespiteSufficientBalance(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY - 1);
        amount = bound(amount, approved + 1, SUPPLY);
        token.approve(SPENDER, approved);
        token.approve(BOB, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, amount)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, amount);
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.allowance(address(this), BOB), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_unfundedDelegatedTransferRestoresApproval(uint256 balance, uint256 amount, bool infinite) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        token.transfer(ALICE, balance);
        uint256 approved = infinite ? type(uint256).max : amount;
        vm.prank(ALICE);
        token.approve(SPENDER, approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), approved);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_infiniteApprovalCanBeReducedThenRevoked(uint256 firstSpend, uint256 replacement) public {
        firstSpend = bound(firstSpend, 0, SUPPLY - 1);
        replacement = bound(replacement, 0, SUPPLY - firstSpend - 1);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, firstSpend));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);

        token.approve(SPENDER, replacement);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, replacement));
        assertEq(token.allowance(address(this), SPENDER), 0);

        token.approve(SPENDER, type(uint256).max);
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(ALICE), firstSpend + replacement);
        assertEq(token.balanceOf(address(this)), SUPPLY - firstSpend - replacement);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalIsIsolatedByOwnerAndSpender(uint256 approved, uint256 spent) public {
        spent = bound(spent, 0, approved < SUPPLY ? approved : SUPPLY);
        token.approve(SPENDER, approved);
        token.approve(BOB, 13);
        vm.prank(ALICE);
        token.approve(SPENDER, 17);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, spent));
        assertEq(token.allowance(address(this), SPENDER), approved == type(uint256).max ? approved : approved - spent);
        assertEq(token.allowance(address(this), BOB), 13);
        assertEq(token.allowance(ALICE, SPENDER), 17);
        assertEq(token.balanceOf(ALICE), spent);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
