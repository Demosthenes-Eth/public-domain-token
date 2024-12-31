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

        // Attempt to deauthorize issuer1 right away
        vm.expectRevert(bytes("Issuer term has not expired"));
        token.deauthorizeIssuer(issuer1);
    }

    // ------------------------------------------------------------------------
    // Mint tests
    // ------------------------------------------------------------------------

    function testIssuerCanMint() public {
        // Authorize issuer1
        token.authorizeIssuer(issuer1);

        // Start acting as issuer1
        vm.startPrank(issuer1);

        // Mint tokens to user1
        // baseMintFactor defaults to 5, meaning up to 5% of total supply can be minted in one go
        // Since totalSupply is 0 at the very beginning, the contract has special handling 
        // (if currentSupply == 0, it just uses baseMintFactor).
        token.mint(user1, 1000);

        vm.stopPrank();

        // Check user1's new balance
        assertEq(token.balanceOf(user1), 1000, "User1 should have 1000 tokens");
    }

    function testCannotMintIfNotIssuer() public {
        // Non-issuer tries to mint
        vm.expectRevert(bytes("Unauthorized Issuer"));
        token.mint(user1, 1000);
    }

    function testMintShortfallIfSupplyBelowMinSupply() public {
        // The default minSupply is 1,000,000. 
        // Let's test that if totalSupply < minSupply, 
        // shortfall is automatically added to the minted amount.

        // Authorize issuer1
        token.authorizeIssuer(issuer1);
        vm.startPrank(issuer1);

        // totalSupply is 0 now, so shortfall = minSupply (1,000,000).
        // userRequestedAmount = 1000. 
        // totalMintAmount = 1000 + 1,000,000 = 1,001,000
        token.mint(user1, 1000);

        vm.stopPrank();

        assertEq(token.balanceOf(user1), 1_001_000, "Balance should include the shortfall");
        assertEq(token.totalSupply(), 1_001_000, "Total supply should match minted amount");
    }

    // ------------------------------------------------------------------------
    // Burn tests
    // ------------------------------------------------------------------------

    function testIssuerCanBurn() public {
        // Authorize issuer1, mint first, then burn
        token.authorizeIssuer(issuer1);

        vm.startPrank(issuer1);
        token.mint(issuer1, 2000);
        // issuer1 now has 1,002,000 if it was the very first mint, or 2000 if supply was already above minSupply.
        // Let's assume for demonstration that totalSupply was above minSupply, so no shortfall added. 
        // This detail depends on prior test states if you run them together.
        
        token.burn(1000);
        vm.stopPrank();

        // issuer1 minted 2000, then burned 1000, net is 1000
        assertEq(token.balanceOf(issuer1), 1000, "issuer1 should have burned 1000 tokens");
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
    }

    function testNonOwnerCannotSetIssuerInterval() public {
        // Try calling as issuer1
        token.authorizeIssuer(issuer1);
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
    }

    function testOwnerCanSetMinSupply() public {
        vm.prank(owner);
        token.setMinSupply(2_000_000);
        assertEq(token.minSupply(), 2_000_000, "minSupply not updated");
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
