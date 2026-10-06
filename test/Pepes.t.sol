// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pepes} from "../src/Pepes.sol";

/// @dev Test-only helper; deployment must credit the factory, not the transaction origin.
contract PepesFactoryProbe {
    function deploy(bytes32 salt) external returns (Pepes) {
        return new Pepes{salt: salt}();
    }

    function send(Pepes token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount));
    }
}

contract PepesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    Pepes private token;

    function setUp() public {
        token = new Pepes();
    }

    function test_metadataAndInitialSupply() public view {
        assertEq(token.name(), "Pepes");
        assertEq(token.symbol(), "PEPES");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), address(this), SUPPLY);
        new Pepes();
    }

    function test_factoryCreate2ReceivesEntireSupply() public {
        PepesFactoryProbe factory = new PepesFactoryProbe();
        bytes32 salt = keccak256("Pepes deployment");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(Pepes).creationCode))
                    )
                )
            )
        );
        vm.prank(ALICE, BOB);
        Pepes deployed = factory.deploy(salt);
        assertEq(address(deployed), predicted);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(ALICE), 0);
        assertEq(deployed.balanceOf(BOB), 0);
    }

    function test_launchDistributionAndPoolTransfersAreExact() public {
        PepesFactoryProbe factory = new PepesFactoryProbe();
        Pepes deployed = factory.deploy(bytes32(uint256(1)));
        address distributor = address(0xD157);
        address poolManager = address(0x9001);
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY / 2; // Test fixture only; deployment economics are external.
        uint256 remainder = SUPPLY - swarm - pool;

        factory.send(deployed, distributor, swarm);
        assertEq(deployed.balanceOf(distributor), swarm);
        vm.prank(distributor);
        assertTrue(deployed.transfer(ALICE, swarm));
        assertEq(deployed.balanceOf(distributor), 0);
        assertEq(deployed.balanceOf(ALICE), swarm);

        factory.send(deployed, poolManager, pool);
        factory.send(deployed, BOB, remainder);
        assertEq(deployed.balanceOf(poolManager), pool);
        assertEq(deployed.balanceOf(BOB), remainder);
        assertEq(deployed.balanceOf(address(factory)), 0);

        // Exercise both token transfer directions without claiming to simulate AMM pricing.
        vm.prank(poolManager);
        assertTrue(deployed.transfer(SPENDER, 123 ether));
        assertEq(deployed.balanceOf(SPENDER), 123 ether);
        assertEq(deployed.balanceOf(poolManager), pool - 123 ether);
        vm.prank(SPENDER);
        assertTrue(deployed.transfer(poolManager, 123 ether));
        assertEq(deployed.balanceOf(SPENDER), 0);
        assertEq(deployed.balanceOf(poolManager), pool);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_transferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 23 ether);
        assertTrue(token.transfer(ALICE, 23 ether));
        assertEq(token.balanceOf(ALICE), 23 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 23 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireSupply() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, SUPPLY));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveReplacesAndRevokesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), SPENDER, 10 ether);
        assertTrue(token.approve(SPENDER, 10 ether));
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertTrue(token.approve(SPENDER, 3 ether));
        assertEq(token.allowance(address(this), SPENDER), 3 ether);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferFromEmitsEventAndConsumesFiniteAllowance() public {
        token.approve(SPENDER, 10 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 4 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 4 ether));
        assertEq(token.allowance(address(this), SPENDER), 6 ether);
        assertEq(token.balanceOf(ALICE), 4 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 6 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 10 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumAllowanceIsNotConsumed() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromToSelfStillConsumesAllowance() public {
        token.approve(SPENDER, 10 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 10 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_revertTransferToZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_revertTransferExceedingBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(ALICE, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_revertApproveZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_revertUnapprovedSpender() public {
        token.approve(SPENDER, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
    }

    function test_revertTransferFromExceedingAllowance() public {
        token.approve(SPENDER, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 10 ether, 10 ether + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 10 ether + 1);
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_revertTransferFromExceedingBalanceRestoresAllowance() public {
        token.approve(SPENDER, SUPPLY + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, SUPPLY + 1);
        assertEq(token.allowance(address(this), SPENDER), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_revertTransferFromToZeroRestoresAllowance() public {
        token.approve(SPENDER, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 10 ether);
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_revokedAllowanceCannotBeSpent() public {
        token.approve(SPENDER, type(uint256).max);
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_deployerCannotTakeHolderTokensWithoutApproval() public {
        token.transfer(ALICE, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 10 ether);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 10 ether));
        assertEq(token.balanceOf(BOB), 10 ether);
    }

    function test_noMintBurnOrAdministrativeEntryPoints() public {
        token.transfer(ALICE, 10 ether);
        string[23] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)",
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)",
            "burn(uint256)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, uint256(1));
            (bool deployerCall,) = address(token).call(data);
            assertFalse(deployerCall, signatures[i]);
            vm.prank(BOB);
            (bool strangerCall,) = address(token).call(data);
            assertFalse(strangerCall, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(ALICE), 10 ether);
            assertEq(token.balanceOf(BOB), 0);
        }
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 10 ether));
        assertEq(token.balanceOf(BOB), 10 ether);
    }

    function test_rejectsNativeCurrency() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_runtimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
        }
    }

    function testFuzz_constructorCreditsImmediateDeployer(address deployer) public {
        vm.assume(deployer != address(0));
        vm.prank(deployer);
        Pepes deployed = new Pepes();
        assertEq(deployed.balanceOf(deployer), SUPPLY);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromHonorsAllowance(uint256 approved, uint256 spent) public {
        approved = bound(approved, 0, SUPPLY);
        spent = bound(spent, 0, approved);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, spent));
        assertEq(token.allowance(address(this), SPENDER), approved - spent);
        assertEq(token.balanceOf(ALICE), spent);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_revertOverspendLeavesStateUnchanged(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - balance);
        token.transfer(ALICE, balance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, balance + excess)
        );
        vm.prank(ALICE);
        token.transfer(BOB, balance + excess);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
