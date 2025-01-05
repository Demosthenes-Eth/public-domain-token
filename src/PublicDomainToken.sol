// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";

interface IPublicDomainToken is IERC20, IERC20Permit, IVotes {
    function authorizeIssuer(address newIssuer) external;
    function transferIssuerAuthorization(address newIssuer) external;
    function deauthorizeIssuer(address existingIssuer) external;
    function deauthorizeAllExpiredIssuers() external;
    function mint(address to, uint256 userRequestedAmount) external;
    function getIssuerMintFactor(address _issuerAddress) external view returns (uint256);
    function getIssuers() external view returns (address[] memory);
    function getExpiredIssuers() external view returns (address[] memory);
}

contract PublicDomainToken is ERC20, ERC20Burnable, ERC20Permit, ERC20Votes, IPublicDomainToken {
    constructor()
        ERC20("Public Domain Token", "PDoT")
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
    uint256 public constant maxIssuers = 1000;

    //Issuer interval is roughly 1 year assuming 12s per block.
    uint256 public constant issuerInterval = 2628000;

    uint256 public totalIssuers;

    //Max percentage of total supply that can be minted per transaction.
    uint256 public constant baseMintFactor = 5;

    //Min token supply (multiplied by scalingFactor due to 18 decimal points)
    uint256 public constant minSupply = 1000000 * scalingFactor;

    //Array of authorized issuer addresses
    address[] public issuers;

    //Maps addresess to integers which indicate the address is authorized (1) or unauthorized (0).
    mapping (address => uint16) public isIssuer;

    //Maps addresses to the Issuer struct which stores their issuer data.
    mapping (address => Issuer) public issuerData;

    event IssuerAuthorized(address indexed issuer, uint256 expirationBlock);
    event IssuerDeauthorized(address indexed issuer, address indexed deauthorizer);
    event IssuerAuthorizationTransferred(address indexed oldIssuer, address indexed newIssuer, uint256 issuerIndex);
    event IssuerActivity(
        address indexed issuer,
        uint256 minted,
        uint256 burned,
        uint256 totalMintedSoFar,
        uint256 totalBurnedSoFar
    );

    //Checks if the address of the function caller is currently a non-expired, authorized issuer.
    modifier onlyIssuer (){
        require(isIssuer[msg.sender] == 1, "Unauthorized Issuer");
        require(block.number < issuerData[msg.sender].expirationBlock, "Expired Issuer");
        _;
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

    //Internal helper function to deauthorize a single address
    function authorizeIssuerInternal(address newIssuer, Issuer memory _issuerData) private {
        issuers[_issuerData.index] = newIssuer;
        issuerData[newIssuer] = _issuerData;
        isIssuer[newIssuer] = 1;
    }

    function transferIssuerAuthorization(address newIssuer) public onlyIssuer {
        require(isIssuer[msg.sender] == 1, "Msg.sender is not an authorized issuer");
        require(isIssuer[newIssuer] == 0, "Address is already authorized");
        require(block.number < issuerData[msg.sender].expirationBlock, "Issuer term has expired");
        require(newIssuer != address(0), "Cannot transfer authorization to address(0)");
        require(newIssuer != address(this), "Cannot transfer authorization to contract address");

        Issuer memory tempData = Issuer(issuerData[msg.sender].index, issuerData[msg.sender].startingBlock, issuerData[msg.sender].expirationBlock, issuerData[msg.sender].totalMinted, issuerData[msg.sender].mintCount, issuerData[msg.sender].burnCount, issuerData[msg.sender].totalBurned);
        deauthorizeIssuerInternal(msg.sender);
        authorizeIssuerInternal(newIssuer, tempData);
        emit IssuerAuthorizationTransferred(msg.sender, newIssuer, tempData.index);
    }

    /*Deauthorizes a single address as long as it's current an authorized issuer 
    and its experiation has passed*/
    function deauthorizeIssuer(address existingIssuer) public {
        require (isIssuer[existingIssuer] == 1, "Address is not an authorized issuer");
        require (msg.sender == existingIssuer || block.number >= issuerData[existingIssuer].expirationBlock, "Issuer term has not expired");
        delete isIssuer[existingIssuer];
        totalIssuers--;
        removeIssuerFromArray(existingIssuer);
        emit IssuerDeauthorized(existingIssuer, msg.sender);
        delete issuerData[existingIssuer];
    }

    //Internal helper function to deauthorize a single address
    function deauthorizeIssuerInternal(address existingIssuer) private {
        delete isIssuer[existingIssuer];
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

        
        if (currentSupply == 0){
            //Force user to mint the minimum supply amount if total supply is 0
            userRequestedAmount = 0;
        } else {
            //Amount of tokens requested can't exceed the allowable number of tokens that can be minted 
            //based on the minter's mint factor
            require(userRequestedAmount * 100 <= currentSupply * mintFactor, "Minted amount exceeds allowable mint");
        }

        uint256 totalMintAmount = userRequestedAmount + shortfall;
        
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

    function getExpiredIssuers() public view returns (address[] memory){
        address[] memory expiredIssuers;
        uint256 expiredCount = 0;
        for (uint i=issuers.length; i > 0; i--){
            uint idx = i - 1;
            if (block.number >= issuerData[issuers[idx]].expirationBlock){
                expiredIssuers[expiredCount] = issuers[idx];
                expiredCount++;
            }
        }
        return expiredIssuers;
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
        require(to != address(this), "Cannot transfer to contract address");
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, IERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }

}