// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "./IPublicDomainToken.sol"; 

contract PublicDomainToken is ERC20, ERC20Burnable, Ownable, ERC20Permit, ERC20Votes {
    constructor(address initialOwner)
        ERC20("Public Domain Token", "PDoT")
        Ownable(initialOwner)
        ERC20Permit("Public Domain Token")
    {}

    struct Issuer {
        uint256 index;
        uint256 startingBlock;
        uint256 expirationBlock;
        uint256 totalMinted;
        uint256 mintCount;
        uint256 burnCount;
        uint256 totalBurned;
    }

    uint256 constant scalingFactor = 1e18;
    
    //Cap on authorized issuers.
    uint256 public maxIssuers = 1000;

    //Issuer interval is roughly 1 year assuming 12s per block.
    uint256 public issuerInterval = 2628000;

    uint256 public totalIssuers;

    //Max percentage of total supply that can be minted per transaction. Arbitrarily set to 5%.
    uint256 public baseMintFactor = 5;

    //Min token supply
    uint256 public minSupply = 1000000;

    //Array of authorized issuer addresses
    address[] public issuers;

    //Maps addresess to integers which indicate the address is authorized (1) or unauthorized (0).
    mapping (address => uint16) public isIssuer;

    //Maps addresses to the Issuer struct which stores their issuer data.
    mapping (address => Issuer) public issuerData;

    event IssuerAuthorized(address indexed issuer, uint256 expirationBlock);
    event IssuerDeauthorized(address indexed issuer, address indexed deauthorizer);
    event IssuerActivity(
        address indexed issuer,
        uint256 minted,
        uint256 burned,
        uint256 totalMintedSoFar,
        uint256 totalBurnedSoFar
    );
    event IssuerIntervalUpdated(uint256 oldInterval, uint256 newInterval);
    event BaseMintFactorUpdated(uint256 oldMintFactor, uint256 newMintFactor);
    event MinSupplyUpdated(uint256 oldMinSupply, uint256 newMinSupply);

    //Checks if the address of the function caller is currently a non-expired, authorized issuer.
    modifier onlyIssuer (){
        require(isIssuer[msg.sender] == 1, "Unauthorized Issuer");
        require(block.number < issuerData[msg.sender].expirationBlock, "Expired Issuer");
        _;
    }

    /*Setter function to change the issuer term for testing purposes. Should be deleted prior to deployment.
    Added onlyOwner modifier as a safety measure in case it accidentally gets deployed.*/
    function setIssuerInterval(uint newInterval) public onlyOwner {
        emit IssuerIntervalUpdated(issuerInterval, newInterval);
        issuerInterval = newInterval;
    }

    /*Setter function to change the base mint factor for testing purposes.  Should be deleted prior to
    deployment. Added onlyOwner modifier as a safety measure in case it accidentally gets deployed.*/
    function setBaseMintFactor(uint newMintFactor) public onlyOwner {
        emit BaseMintFactorUpdated(baseMintFactor, newMintFactor);
        baseMintFactor = newMintFactor;
    }

    /*Setter function to change the minimum supply for testing purposes.  Should be deleted prior to
    deployment. Added onlyOwner modifier as a safety measure in case it accidentally gets deployed.*/
    function setMinSupply(uint256 newMinSupply) public onlyOwner {
        emit MinSupplyUpdated(minSupply, newMinSupply);
        minSupply = newMinSupply;
    }

    /*Authorizes an address as an issuer if the address is not already authorized
    and the total number of issuers is less than the issuer cap*/
    function authorizeIssuer(address newIssuer) public {
        require(isIssuer[newIssuer] == 0, "Address is already authorized");
        require(totalIssuers < maxIssuers, "Maximum number of Issuers reached");
        totalIssuers++;
        issuers.push(newIssuer);
        isIssuer[newIssuer] = 1;
        issuerData[newIssuer] = Issuer(issuers.length - 1, block.number, block.number + issuerInterval, 0, 0, 0, 0);
        emit IssuerAuthorized(newIssuer, issuerData[newIssuer].expirationBlock);
    }

    /*Deauthorizes a single address as long as it's current an authorized issuer 
    and its experiation has passed*/
    function deauthorizeIssuer(address existingIssuer) public {
        require (isIssuer[existingIssuer] == 1, "Address is not an authorized issuer");
        require (block.number >= issuerData[existingIssuer].expirationBlock, "Issuer term has not expired");
        delete isIssuer[existingIssuer];
        totalIssuers--;
        removeIssuerFromArray(existingIssuer);
        emit IssuerDeauthorized(existingIssuer, msg.sender);
        delete issuerData[existingIssuer];
    }

    //Loops through issuers array and deauthorizes any addresses whose expiration has passed
    function deauthorizeAllExpiredIssuers() public {
        for (uint i = issuers.length; i > 0; i--) {
            uint idx = i - 1;
            if (block.number >= issuerData[issuers[idx]].expirationBlock) {
                address expired = issuers[idx];
                delete isIssuer[expired];
                totalIssuers--;
                removeIssuerFromArray(expired);
                emit IssuerDeauthorized(expired, msg.sender);
                delete issuerData[expired];
            }
        }
    }

    function mint(address to, uint256 userRequestedAmount) public onlyIssuer {
        require(to != address(0), "ERC20: mint to the zero address");
        require(to != address(this), "Cannot mint tokens to the contract address");

        uint256 currentSupply = totalSupply();

        if(currentSupply != 0){
            require(userRequestedAmount > 0, "Minted amount must be greater than 0");
        }

        uint256 mintFactor = calculateMintFactor(msg.sender);
        

        uint256 shortfall = 0;
        if(currentSupply < minSupply){
            shortfall = minSupply - currentSupply;
        }

        uint256 totalMintAmount = userRequestedAmount + shortfall;

        //Amount of tokens requested can't exceed the allowable number of tokens that can be minted 
        //based on the minter's mint factor
        require(userRequestedAmount * 100 <= currentSupply * mintFactor, "Minted amount exceeds allowable mint");
        
        _mint(to,totalMintAmount);
        issuerData[msg.sender].totalMinted += totalMintAmount;
        issuerData[msg.sender].mintCount++;
        emit IssuerActivity(msg.sender, totalMintAmount, 0, issuerData[msg.sender].totalMinted, issuerData[msg.sender].totalBurned);
    }

    //Added logic to update burn data for issuer
    function burn(uint256 amount) public override onlyIssuer {
        _burn(msg.sender, amount);
        issuerData[msg.sender].totalBurned +=amount;
        issuerData[msg.sender].burnCount++;
        emit IssuerActivity(msg.sender, 0, amount, issuerData[msg.sender].totalMinted, issuerData[msg.sender].totalBurned);
    }

    //Added logic to update burn data for issuer
    function burnFrom(address account, uint256 amount) public override onlyIssuer {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
        issuerData[msg.sender].totalBurned += amount;
        issuerData[msg.sender].burnCount++;
    }

    //Determines max amount of tokens that can be issued in the transaction
    //as a percentage of the current supply

    function calculateMintFactor(address _issuerAddress) view internal returns (uint256){
        uint256 totalMinted = issuerData[_issuerAddress].totalMinted;
        uint256 mintCount = issuerData[_issuerAddress].mintCount;
        uint256 burnCount = issuerData[_issuerAddress].burnCount;
        uint256 totalBurned = issuerData[_issuerAddress].totalBurned;
        
        uint256 currentSupply = totalSupply();

        if(currentSupply == 0){
            return baseMintFactor;
        }

        //Average number of tokens minted per mint, scaled by scaling factor
        uint256 scaledAvgMint = (mintCount == 0) ? 0 : (totalMinted * scalingFactor) / mintCount;

        //Average number of tokens burned per burn, scaled by scaling factor
        uint256 scaledAvgBurn = (burnCount == 0) ? 0 : (totalBurned * scalingFactor) / burnCount;

        //Average percentage of current total supply minted per mint
        uint256 scaledAvgPercentMint = (scaledAvgMint * 100) / (scalingFactor * currentSupply);
        
        uint256 mintAdjustedBase;

        //Clip to 0 if scaled avg percent mint is greater than base mint factor
        if (scaledAvgPercentMint >= baseMintFactor) {
            mintAdjustedBase = 0;
        } else {
            //Reduce base mint factor by the average percentage of current total supply minted per mint
            mintAdjustedBase = baseMintFactor - scaledAvgPercentMint;
        }

        uint256 burnOffset;

        //If address has burned more tokens in aggregate than it has minted
        if (totalMinted <= totalBurned){
            burnOffset+=1;
            }
        //If the average number of tokens burned per burn is higher than the
        //average number of tokens minted per mint
        if (scaledAvgMint <= scaledAvgBurn){
            burnOffset+=1;
        }
        //If the average number of tokens minted per mint 
        //is less than 2% of the current supply
        if (scaledAvgPercentMint <= 2){
            burnOffset+=1;
        }

        uint256 finalBase = mintAdjustedBase + burnOffset;

        if (finalBase > baseMintFactor){
            return baseMintFactor;
        } else {
            return finalBase;
        }
    }

    function getIssuerMintFactor(address _issuerAddress) public view returns (uint256){
        return calculateMintFactor(_issuerAddress);
    }

    //Returns the entire array of issuers so users can easily see 
    //which addresses are currently authorized issuers at any time.
    function getIssuers() public view returns (address[] memory){
        return issuers;
    }

    function removeIssuerFromArray(address issuer) internal {
        uint idx = issuerData[issuer].index;
        uint lastIdx = issuers.length - 1;

        if (idx != lastIdx) {                       
            address lastIssuer = issuers[lastIdx];  
            issuers[idx] = lastIssuer;              
            issuerData[lastIssuer].index = idx;     
        }
        issuers.pop();                              
    }

    //The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }

}