// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../lib/forge-std/src/Test.sol";
// Adjust the path if your PublicDomainToken is in a different location
import "../PublicDomainToken.sol";

contract PublicDomainTokenTest is Test {
    // ------------------------------------------------------------------------
    // State variables & setup
    // ------------------------------------------------------------------------
    
    PublicDomainToken internal token;

    address internal owner   = address(100);
    address internal issuer1 = address(101);
    address internal issuer2 = address(102);
    address internal user1   = address(103);

    function setUp() public {
        // Deploy the contract with `owner` as the initialOwner
        vm.prank(owner);
        token = new PublicDomainToken(owner);
    }

    // ------------------------------------------------------------------------
    // Basic constructor tests
    // ------------------------------------------------------------------------

    function testConstructorSetsOwner() public {
        // The `Ownable` part is inherited from an OZ contract that has 
        // been modified to accept an initialOwner in the constructor.
        // We expect the owner to be `address(100)`.
        assertEq(token.owner(), owner, "Owner not set correctly in constructor");
    }

    function testTokenNameAndSymbol() public {
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

        // The index, totalMinted, etc. from issuer1 should have transferred to issuer2
        // Let's verify the index at least:
        assertEq(
            token.issuerData(issuer2).index,
            0, // Because issuer1 had index 0 when we first authorized it (assuming it was the first authorized)
            "issuer2 should have inherited issuer1's original index"
        );
    }

    function testTransferIssuerAuthorizationCopiesStats() public {   
        vm.prank(issuer1);
        token.mint(issuer1, 1000); 
        
        // Grab issuer1's data before transferring authorization
        PublicDomainToken.Issuer memory oldIssuerData = token.issuerData(issuer1);

        // Confirm issuer1’s data was updated
        // totalMinted should be exactly 1,000,000
        assertEq(
            oldIssuerData.totalMinted,
            1_000_000,
            "issuer1's totalMinted should reflect only the shortfall"
        );
        assertEq(
            oldIssuerData.mintCount,
            1,
            "issuer1's mintCount should have incremented to 1"
        );

        // Transfer authorization from issuer1 -> issuer2
        vm.prank(issuer1);
        token.transferIssuerAuthorization(issuer2);

        // issuer1 should now be deauthorized
        assertEq(token.isIssuer(issuer1), 0, "old issuer1 should be deauthorized");

        // issuer2 should now be authorized
        assertEq(token.isIssuer(issuer2), 1, "issuer3 should be authorized");

        // Check that issuer2 inherited issuer1’s data
        PublicDomainToken.Issuer memory newIssuerData = token.issuerData(issuer2);

        // All stats, including totalMinted, are copied over
        assertEq(
            newIssuerData.totalMinted,
            oldIssuerData.totalMinted,
            "issuer2 should inherit the totalMinted count"
        );
        assertEq(
            newIssuerData.mintCount,
            oldIssuerData.mintCount,
            "issuer2 should inherit the mintCount"
        );
        assertEq(
            newIssuerData.burnCount,
            oldIssuerData.burnCount,
            "issuer2 should inherit the burnCount"
        );
        assertEq(
            newIssuerData.totalBurned,
            oldIssuerData.totalBurned,
            "issuer2 should inherit the totalBurned"
        );
        assertEq(
            newIssuerData.index,
            oldIssuerData.index,
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
        uint256 expirationBlock = token.issuerData(issuer1).expirationBlock;
         vm.roll(expirationBlock + 1); // now past expiration

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
        vm.startPrank(issuer1);
        vm.expectEmit(true, true, false, true);
        emit token.IssuerAuthorizationTransferred(issuer1, issuer2, token.issuerData(issuer1).index);
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

    function testMintShortfallIfSupplyBelowMinSupply() public {
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
    }

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
    // Owner-only setters
    // ------------------------------------------------------------------------

    function testOwnerCanSetIssuerInterval() public {
        // default issuerInterval is 2628000
        uint256 oldInterval = token.issuerInterval();
        uint256 newInterval = 1000000;

        vm.prank(owner);
        token.setIssuerInterval(newInterval);

        assertEq(token.issuerInterval(), newInterval, "Issuer interval not updated");
        assertTrue(token.issuerInterval() != oldInterval, "Issuer interval should change");
        vm.stopPrank();

        // Try calling as issuer1
        vm.startPrank(issuer1);

        vm.expectRevert(
        abi.encodeWithSelector(
            Ownable.OwnableUnauthorizedAccount.selector,
            issuer1
        )
        );
        token.setIssuerInterval(newInterval);

        vm.stopPrank();
    }

    function testNonOwnerCannotSetIssuerInterval() public {
        // Try calling as issuer1
        vm.startPrank(issuer1);

        vm.expectRevert(
        abi.encodeWithSelector(
            Ownable.OwnableUnauthorizedAccount.selector,
            issuer1
        )
        );
        token.setIssuerInterval(123456);

        vm.stopPrank();
    }

    function testOwnerCanSetBaseMintFactor() public {
        vm.prank(owner);
        token.setBaseMintFactor(10);
        assertEq(token.baseMintFactor(), 10, "baseMintFactor not updated");
        vm.stopPrank();

        // Try calling as issuer1
        vm.startPrank(issuer1);

        vm.expectRevert(
        abi.encodeWithSelector(
            Ownable.OwnableUnauthorizedAccount.selector,
            issuer1
        )
        );
        token.setBaseMintFactor(10);

        vm.stopPrank();
    }

    function testOwnerCanSetMinSupply() public {
        vm.prank(owner);
        token.setMinSupply(2_000_000);
        assertEq(token.minSupply(), 2_000_000, "minSupply not updated");
        vm.stopPrank();

        // Try calling as issuer1
        vm.startPrank(issuer1);

        vm.expectRevert(
        abi.encodeWithSelector(
            Ownable.OwnableUnauthorizedAccount.selector,
            issuer1
        )
        );
        token.setMinSupply(1000000);

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
}
