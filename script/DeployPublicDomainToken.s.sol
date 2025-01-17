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

        vm.startBroadcast(privateKey);


        PublicDomainToken token = new PublicDomainToken();


        vm.stopBroadcast();
    }
}
