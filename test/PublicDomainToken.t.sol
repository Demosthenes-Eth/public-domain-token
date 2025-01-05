// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../lib/forge-std/src/Test.sol";
// Adjust the path if your PublicDomainToken is in a different location
import "../src/PublicDomainToken.sol";

contract PublicDomainTokenTest is Test {
    // ------------------------------------------------------------------------
    // State variables & setup
    // ------------------------------------------------------------------------
    
    PublicDomainToken internal token;

    address internal owner   = address(100);
    address internal issuer1 = address(101);
    address internal issuer2 = address(102);
    address internal user1   = address(103);

    event IssuerAuthorizationTransferred(
        address indexed oldIssuer,
        address indexed newIssuer,
        uint256 issuerIndex
    );

    function setUp() public {
        // Deploy the contract with `owner` as the initialOwner
        token = new PublicDomainToken();
    }

    // ------------------------------------------------------------------------
    // Basic constructor tests
    // ------------------------------------------------------------------------

    function testTokenNameAndSymbol() public view {
        // Name should be "Public Domain Token", symbol should be "PDoT"
        assertEq(token.name(), "Public Domain Token");
        assertEq(token.symbol(), "PDoT");
    }

    // ------------------------------------------------------------------------
    // Authorize / Deauthorize Issuers
    // ------------------------------------------------------------------------

    function testAuthorizeIssuer() public {
        // We call authorizeIssuer as `owner` (or any caller) 
        // because there's no onlyOwner restriction on authorizeIssuer 
        // in the contract. Just do it as the default msg.sender.
        token.authorizeIssuer(issuer1);

        // Check if issuer1 is now authorized
        // `isIssuer[issuer] == 1` means authorized
        assertEq(token.isIssuer(issuer1), 1, "Issuer1 should be authorized");

        // Check that totalIssuers is incremented
        assertEq(token.totalIssuers(), 1, "Total issuers should be 1");
    }

    function testCannotAuthorizeSameIssuerTwice() public {
        token.authorizeIssuer(issuer1);

        // Try authorizing issuer1 again:
        vm.expectRevert(bytes("Address is already authorized"));
        token.authorizeIssuer(issuer1);
    }

    function testDeauthorizeIssuerAfterExpiration() public {
        // Authorize an issuer
        token.authorizeIssuer(issuer1);

        // We get back a tuple with 7 fields: 
        // (index, startingBlock, expirationBlock, totalMinted, mintCount, burnCount, totalBurned)
        (, , uint256 expirationBlock, , , , ) = token.issuerData(issuer1);

        // Advance the block beyond expirationBlock
        vm.roll(expirationBlock);
        vm.roll(block.number + 1);

        // Now deauthorize
        token.deauthorizeIssuer(issuer1);
        assertEq(token.isIssuer(issuer1), 0, "Issuer1 should be deauthorized");
        assertEq(token.totalIssuers(), 0, "Total issuers should decrement");
    }

    function testCannotDeauthorizeIssuerBeforeExpiration() public {
        // Authorize an issuer
        token.authorizeIssuer(issuer1);
        vm.startPrank(issuer2);
        // Attempt to deauthorize issuer1 right away
        vm.expectRevert(bytes("Issuer term has not expired"));
        token.deauthorizeIssuer(issuer1);
        vm.stopPrank();

        // issuer1 should still be authorized
        // Attempt to deauthorize issuer 1 again as issuer1

        vm.startPrank(issuer1);
        token.deauthorizeIssuer(issuer1);
        assertEq(token.isIssuer(issuer1), 0, "Issuer1 should be deauthorized");
        vm.stopPrank();
    }

    function testTransferAuthorizationShouldSucceed() public {
        token.authorizeIssuer(issuer1);
        vm.startPrank(issuer1);
        // Transfer issuer1's authorization to issuer2
        token.transferIssuerAuthorization(issuer2);
        vm.stopPrank();

        // Now issuer1 should NOT be an issuer
        assertEq(token.isIssuer(issuer1), 0, "issuer1 should no longer be an issuer");

        // issuer2 should now be an issuer
        assertEq(token.isIssuer(issuer2), 1, "issuer2 should be newly authorized");

        (
            uint256 iIndex,
            uint256 iStartingBlock,
            uint256 iExpirationBlock,
            uint256 iTotalMinted,
            uint256 iMintCount,
            uint256 iBurnCount,
            uint256 iTotalBurned
        ) = token.issuerData(issuer2);

        // The index, totalMinted, etc. from issuer1 should have transferred to issuer2
        // Let's verify the index at least:
        assertEq(
            iIndex,
            0, // Because issuer1 had index 0 when we first authorized it (assuming it was the first authorized)
            "issuer2 should have inherited issuer1's original index"
        );
    }

    function testTransferIssuerAuthorizationCopiesStats() public {   
        token.authorizeIssuer(issuer1);
        vm.prank(issuer1);
        token.mint(issuer1, 1000); 
        
        // Grab issuer1's data before transferring authorization
        (
            uint256 iIndex,
            uint256 iStartingBlock,
            uint256 iExpirationBlock,
            uint256 iTotalMinted,
            uint256 iMintCount,
            uint256 iBurnCount,
            uint256 iTotalBurned
        ) = token.issuerData(issuer1);

        // Confirm issuer1’s data was updated
        // totalMinted should be exactly 1,000,000
        assertEq(
            iTotalMinted,
            1_000_000,
            "issuer1's totalMinted should reflect only the shortfall"
        );
        assertEq(
            iMintCount,
            1,
            "issuer1's mintCount should have incremented to 1"
        );

        // Transfer authorization from issuer1 -> issuer2
        vm.prank(issuer1);
        token.transferIssuerAuthorization(issuer2);

        // issuer1 should now be deauthorized
        assertEq(token.isIssuer(issuer1), 0, "old issuer1 should be deauthorized");

        // issuer2 should now be authorized
        assertEq(token.isIssuer(issuer2), 1, "issuer2 should be authorized");

        // Check that issuer2 inherited issuer1’s data
        (
            uint256 jIndex,
            uint256 jStartingBlock,
            uint256 jExpirationBlock,
            uint256 jTotalMinted,
            uint256 jMintCount,
            uint256 jBurnCount,
            uint256 jTotalBurned
        ) = token.issuerData(issuer2);

        // All stats, including totalMinted, are copied over
        assertEq(
            iTotalMinted,
            jTotalMinted,
            "issuer2 should inherit the totalMinted count"
        );
        assertEq(
            iMintCount,
            jMintCount,
            "issuer2 should inherit the mintCount"
        );
        assertEq(
           iBurnCount,
           jBurnCount,
            "issuer2 should inherit the burnCount"
        );
        assertEq(
            iTotalBurned,
            jTotalBurned,
            "issuer2 should inherit the totalBurned"
        );
        assertEq(
            iIndex,
            jIndex,
            "issuer2 should inherit issuer1's index in the issuers array"
        );
    }

    function testTransferFailsIfNewIssuerIsAlreadyAuthorized() public {
            // issuer2 is already an issuer, so transferring issuer1’s authorization to issuer2 should revert
            token.authorizeIssuer(issuer1);
            token.authorizeIssuer(issuer2);

            vm.startPrank(issuer1);
            vm.expectRevert(bytes("Address is already authorized"));
            token.transferIssuerAuthorization(issuer2);
            vm.stopPrank();
    }

    function testTransferFailsIfCallerIsNotAnIssuer() public {
        token.authorizeIssuer(issuer1);
        // user1 is not an issuer, tries to transfer
        vm.startPrank(user1);
        vm.expectRevert(bytes("Unauthorized Issuer"));
        token.transferIssuerAuthorization(issuer2);
        vm.stopPrank();
    }

    function testTransferFailsIfCallerIsExpired() public {
        token.authorizeIssuer(issuer1);
        // We’ll artificially roll the block number to issuer1’s expiration
        (
            uint iIndex,
            uint iStartingBlock,
            uint iExpirationBlock,
            uint iTotalMinted,
            uint iMintCount,
            uint iBurnCount,
            uint iTotalBurned
        ) = token.issuerData(issuer1);
         vm.roll(iExpirationBlock + 1); // now past expiration

        vm.startPrank(issuer1);
        vm.expectRevert(bytes("Expired Issuer"));
        token.transferIssuerAuthorization(issuer2);
        vm.stopPrank();
    }

    function testTransferFailsIfNewIssuerIsZeroAddress() public {
        token.authorizeIssuer(issuer1);
        vm.startPrank(issuer1);
        vm.expectRevert(bytes("Cannot transfer authorization to address(0)"));
        token.transferIssuerAuthorization(address(0));
        vm.stopPrank();
    }

    function testTransferFailsIfNewIssuerIsContractItself() public {
        token.authorizeIssuer(issuer1);
        vm.startPrank(issuer1);
        vm.expectRevert(bytes("Cannot transfer authorization to contract address"));
        token.transferIssuerAuthorization(address(token));
        vm.stopPrank();
    }

    function testTransferEmitsEvent() public {
        // We can check the event logs for IssuerAuthorizationTransferred
        token.authorizeIssuer(issuer1);
        (
            uint iIndex,
            uint iStartingBlock,
            uint iExpirationBlock,
            uint iTotalMinted,
            uint iMintCount,
            uint iBurnCount,
            uint iTotalBurned
        ) = token.issuerData(issuer1);
        vm.startPrank(issuer1);
        vm.expectEmit(true, true, false, true);
        emit IssuerAuthorizationTransferred(issuer1, issuer2, iIndex);
        token.transferIssuerAuthorization(issuer2);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------------
    // Mint tests
    // ------------------------------------------------------------------------

    function testIssuerCanMint() public {
        // Authorize issuer1
        token.authorizeIssuer(issuer1);

        // Act as issuer1
        vm.startPrank(issuer1);

        // currentSupply == 0
        // Because your new logic says: if supply == 0, disregard userRequestedAmount
        // and mint exactly `minSupply` (1,000,000).
        token.mint(user1, 1000);

        vm.stopPrank();

        // We now expect user1 to have 1,000,000 tokens (not 1,001,000).
        assertEq(
            token.balanceOf(user1),
            1_000_000,
            "User1 should have 1,000,000 tokens"
        );

        // Total supply is also 1,000,000
        assertEq(
            token.totalSupply(),
            1_000_000,
            "Total supply should be 1,000,000"
        );
    }

    function testCannotMintIfNotIssuer() public {
        // Non-issuer tries to mint
        vm.expectRevert(bytes("Unauthorized Issuer"));
        token.mint(user1, 1000);
    }

    /*Successfully tested testMintShortFallIfSupplyBelowMinSupply() previously
    and disabling now due to fact that it relies on ownership of the contract
    to change minSupply since contract ownership no longer applies.*/
    /* function testMintShortfallIfSupplyBelowMinSupply() public {
        // Authorize issuer1
        token.authorizeIssuer(issuer1);
        vm.startPrank(issuer1);

        // ----------------------------------------------------------------------
        // 1) First mint from zero supply
        //    supply == 0 => contract ignores userRequested(500)
        //    and mints exactly minSupply(1,000,000).
        // ----------------------------------------------------------------------
        token.mint(issuer1, 500); 
        // Now totalSupply == 1,000,000
        // issuer1 balance == 1,000,000
        vm.stopPrank();

        // ----------------------------------------------------------------------
        // 2) Increase minSupply to 2,000,000
        //    so totalSupply(1,000,000) < new minSupply(2,000,000)
        // ----------------------------------------------------------------------
        vm.prank(owner);
        token.setMinSupply(2_000_000);

        // ----------------------------------------------------------------------
        // 3) Mint again from a non-zero supply
        //    Now supply(1,000,000) < minSupply(2,000,000)
        //    shortfall = 2,000,000 - 1,000,000 = 1,000,000
        //    userRequested = 1,000
        //    totalMintAmount = 1,000,000 + 1,000 = 1,001,000
        // ----------------------------------------------------------------------
        token.authorizeIssuer(issuer2);
        vm.startPrank(issuer2);

        token.mint(user1, 1_000); 
        vm.stopPrank();

        // user1 got 1,001,000
        // totalSupply = 1,000,000 (first mint) + 1,001,000 (second mint) = 2,001,000

        assertEq(
            token.balanceOf(user1),
            1_001_000,
            "Balance should be 1,001,000"
        );

        assertEq(
            token.totalSupply(),
            2_001_000,
            "Total supply should be 2,001,000"
        );
    } */

    // ------------------------------------------------------------------------
    // Burn tests
    // ------------------------------------------------------------------------

    function testIssuerCanBurn() public {
        // Authorize issuer1
        token.authorizeIssuer(issuer1);

        vm.startPrank(issuer1);

        // currentSupply == 0 => mint = minSupply(1,000,000), ignoring userRequested(2,000).
        token.mint(issuer1, 2_000);

        // issuer1 now has 1,000,000
        // Burn 1,000 => final = 999,000
        token.burn(1_000);

        vm.stopPrank();

        // issuer1's final balance is 999,000
        assertEq(
            token.balanceOf(issuer1),
            999_000,
            "issuer1 should have 999,000 after burning 1,000"
        );
    }

    function testNonIssuerCannotBurn() public {
        // user1 tries to burn
        vm.startPrank(user1);
        vm.expectRevert("Unauthorized Issuer");
        token.burn(100);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------------
    // Utility: test deauthorizeAllExpiredIssuers()
    // ------------------------------------------------------------------------

    function testDeauthorizeAllExpiredIssuers() public {
        // Authorize two issuers
        token.authorizeIssuer(issuer1);
        token.authorizeIssuer(issuer2);

        // Roll blocks forward so that both issuers are expired
        vm.roll(block.number + token.issuerInterval() + 1);

        // Deauthorize them in a single call
        token.deauthorizeAllExpiredIssuers();

        // Both should be gone
        assertEq(token.totalIssuers(), 0, "All expired issuers should be removed");
        assertEq(token.isIssuer(issuer1), 0, "Issuer1 should be removed");
        assertEq(token.isIssuer(issuer2), 0, "Issuer2 should be removed");
    }

    // ------------------------------------------------------------------------
    // Test transfers to contract address
    // ------------------------------------------------------------------------
    
    function testTransferToContractAddressReverts() public {
        token.authorizeIssuer(issuer1);
        vm.startPrank(issuer1);
        token.mint(issuer1, 1000);
        vm.expectRevert(bytes("Cannot transfer to contract address"));
        token.transfer(address(token), 100);

        // Confirm that issuer1's balance is unchanged and
        // the contract address did not receive tokens.
        assertEq(token.balanceOf(issuer1), 1_000_000, "Issuer1 balance should remain 1,000,000");
        assertEq(token.balanceOf(address(token)), 0, "Contract address should have 0 tokens");
        vm.stopPrank();
    }
}
