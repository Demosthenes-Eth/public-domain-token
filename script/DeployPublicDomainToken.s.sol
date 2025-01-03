// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/PublicDomainToken.sol";

contract DeployPublicDomainToken is Script {
    function setUp() public {}
    
    function run() external {
        uint privateKey = vm.envUint("DEV_PRIVATE_KEY");
        address account = vm.addr(privateKey);

        console.log("Account", account);
        // Start broadcasting transactions using the specified profile (Sepolia)
        vm.startBroadcast();

        // Deploy the PublicDomainToken contract without passing an initial owner
        PublicDomainToken token = new PublicDomainToken();

        // Optionally, log the deployed contract address
        //emit log_named_address("PublicDomainToken deployed to:", address(token));

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}