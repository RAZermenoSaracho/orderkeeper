// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DemoUSDC} from "../src/DemoUSDC.sol";

/// @title DemoUSDCTest
/// @notice Unit tests for DemoUSDC: minting and standard ERC20 behavior
///         inherited from OpenZeppelin (transfer, approve/transferFrom).
contract DemoUSDCTest is Test {
    DemoUSDC internal token;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        token = new DemoUSDC();
    }

    // =============================================================
    //                          METADATA
    // =============================================================

    /// @notice Tests name/symbol/decimals match real USDC's convention.
    function test_Metadata() public view {
        assertEq(token.name(), "Demo USD");
        assertEq(token.symbol(), "mUSDC");
        assertEq(token.decimals(), 6);
    }

    // =============================================================
    //                            MINT
    // =============================================================

    /// @notice Tests that minting increases both balance and totalSupply.
    function test_Mint_IncreasesBalanceAndTotalSupply() public {
        uint256 amount = 1_000e6;

        token.mint(alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), amount);
    }

    /// @notice Tests that repeated mints to the same address accumulate.
    function test_Mint_Accumulates() public {
        token.mint(alice, 100e6);
        token.mint(alice, 50e6);

        assertEq(token.balanceOf(alice), 150e6);
        assertEq(token.totalSupply(), 150e6);
    }

    /// @notice Tests that minting to different recipients tracks each
    ///         balance independently while totalSupply reflects the sum.
    function test_Mint_MultipleRecipients() public {
        token.mint(alice, 100e6);
        token.mint(bob, 200e6);

        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.balanceOf(bob), 200e6);
        assertEq(token.totalSupply(), 300e6);
    }

    /// @notice Tests that mint is unrestricted — any caller can mint to any
    ///         address, per its own NatSpec disclaimer (testnet-only faucet
    ///         token, not a real asset, not audited).
    function test_Mint_UnrestrictedAnyCallerCanMint() public {
        vm.prank(stranger);
        token.mint(alice, 42e6);

        assertEq(token.balanceOf(alice), 42e6);
    }

    /// @notice Tests that minting zero is a harmless no-op, not a revert.
    function test_Mint_ZeroAmount() public {
        token.mint(alice, 0);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), 0);
    }

    // =============================================================
    //                      STANDARD ERC20: TRANSFER
    // =============================================================

    /// @notice Tests a standard transfer moves balance correctly.
    function test_Transfer() public {
        token.mint(alice, 100e6);

        vm.prank(alice);
        bool success = token.transfer(bob, 40e6);

        assertTrue(success);
        assertEq(token.balanceOf(alice), 60e6);
        assertEq(token.balanceOf(bob), 40e6);
    }

    /// @notice Tests that transferring more than the sender's balance
    ///         reverts with OZ's standard ERC20InsufficientBalance error.
    function test_RevertWhen_TransferExceedsBalance() public {
        token.mint(alice, 10e6);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("ERC20InsufficientBalance(address,uint256,uint256)", alice, 10e6, 20e6));
        // Return value is unreachable — the call above always reverts.
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transfer(bob, 20e6);
    }

    // =============================================================
    //                 STANDARD ERC20: APPROVE / TRANSFERFROM
    // =============================================================

    /// @notice Tests the standard approve + transferFrom flow, including
    ///         that the allowance is decremented by the amount spent.
    function test_ApproveAndTransferFrom() public {
        token.mint(alice, 100e6);

        vm.prank(alice);
        bool approved = token.approve(bob, 50e6);
        assertTrue(approved);
        assertEq(token.allowance(alice, bob), 50e6);

        vm.prank(bob);
        bool success = token.transferFrom(alice, bob, 30e6);

        assertTrue(success);
        assertEq(token.balanceOf(alice), 70e6);
        assertEq(token.balanceOf(bob), 30e6);
        assertEq(token.allowance(alice, bob), 20e6);
    }

    /// @notice Tests that transferFrom beyond the approved allowance
    ///         reverts with OZ's standard ERC20InsufficientAllowance error.
    function test_RevertWhen_TransferFromExceedsAllowance() public {
        token.mint(alice, 100e6);

        vm.prank(alice);
        token.approve(bob, 10e6);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("ERC20InsufficientAllowance(address,uint256,uint256)", bob, 10e6, 20e6));
        // Return value is unreachable — the call above always reverts.
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transferFrom(alice, bob, 20e6);
    }
}
