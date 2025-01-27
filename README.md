# Public Domain Token

## Introduction

`Public Domain Token`, aka `PDoT`, is an ERC20 token with customized, non-standard minting logic designed to be permissionless, open, decentralized, and use-case agnostic.  Minting and burning is controlled by a class of addresses called Issuers, whose scope and term duration is determined by internal smart contract logic.  Any address can become an Issuer as long as the internal smart contract conditions are satisfied.  This is intended to make PDoT a flexible, shared cross-community asset that can serve different purposes for different stakeholders.

## Motivation

Typical ERC20 token generation events distribute tokens to users via staking, mining, minting through governance, or pre-minting.

In many, if not most cases, total supply of the token is capped in imitation of Bitcoin's original supply model.  Typically, issuance is controlled by one party, even if that party abdicates their control after the TGE.  

Tokens are usually issued for a specific purpose, such as:
- DAO Governance
- Product Parameter Management
- Gaming Utility
- Representatons of Debt or Other Onchain Obligations
- Product-specific Medium of Exchange

The token issuer is typically a stakeholder in whatever utility is intended for the token.

The above covers a broad swathe of the existing ERC20 tokens in existence today, although it's certainly not exhaustive.

In contrast, `Public Domain Token` is intended to invert some of the typical ERC20 norms in an attempt to experimentally examine how user behavior might change in response to differing incentive structures.

It makes two major tradeoffs:

1. Instead of one owner address with exclusive minting authority, the token implements an authorized issuer list that is completely open and permissionless save for a hard cap on the number of authorized issuers at any given time.  Any address can authorize itself as an issuer as long as the cap has not been reached.
2. Instead of a capped token supply, issuers have the ability to mint and burn tokens an arbitrary number of times as long as their address is still authorized.  The amount of tokens they can mint is limited by hardcoded smart contract logic based on a base factor relative to the total supply of the token combined with the issuer's history interacting with the contract.

Functionally, the 2nd tradeoff means that the more an issuer mints, the less tokens they will be able to mint in the future.  However, issuers can manage this with an offset earned by burning tokens.  

It's up to individual issuers to decide what ratio of minting to burning best suits their purposes.

After deployment, the ownership of the contract will be transferred to itself, intentionally bricking any of the ownerOnly setter functions.  

None of the contract parameters will be governable.  The operation of the contract will be entirely autonomous and deterministic based on the existing deployed code.  Once ownership has been transferred to the contract itself, the contract will require no maintenance or further involvement from the original developer.

However, the token is built off of OpenZeppelin's contract libraries including `ERC20Burnable`, `ERC20Permit`, and `ERC20Votes`.  This is intended to give the token a wide range of potential utility such that issuers can choose to use the token for a number of different purposes.

Public Domain Token is an experimental, open token.  Any party can use the token for any purpose, as long as they consider the fact that they will not be the only authorized issuer at any given time.  

From a tokenomics perspective, this introduces interesting new areas for experimentation, game theory, and observation:

- Will issuers coordinate and collaborate to maintain the health of the token ecosystem and all of the various connected stakeholders?  Will the issuer ecosystem devolve into pure PvP?
- Will the token supply inflate beyond control?  Will issuers successfully regulate token supply through burning?
- Is DAO governance feasible in the absence of a closed token system?
- Is game utility feasible in the absence of founder-controlled issuance?

## Documentation

### 1. Overview
- **Name:** Public Domain Token
- **Symbol:** PDoT
- **Decimals:** 18
- **Etherscan Link:** https://etherscan.io/address/0xfabe8869539b6815ad9d60b2103f8ae0ae3fd286
- **Mainnet Ethereum Address:** 0xFABe8869539b6815ad9D60b2103f8Ae0aE3FD286
- **Sepolia Ethereum Testnet Address:** 0xFABe8869539b6815ad9D60b2103f8Ae0aE3FD286
- **Token Standard:** ERC20 (with additional capabilities)
- **Core Features:**
  - Standard ERC20 transfers.
  - ERC20Permit (gasless approvals).
  - ERC20Votes (voting/polling capabilities).
  - Burnable by authorized issuers.
  - Special “issuer” system for minting and burning tokens.

**Important:** The contract has additional controls and logic that differ from a typical ERC20:

1. **Min Supply:** If total supply is 0, the first mint automatically brings supply up to a minimum threshold.
2. **Issuers:** Certain authorized addresses can mint/burn under constraints.

### 2. Basic ERC20 Functionality

**2.1 Transferring Tokens**
- Like any ERC20, you can send tokens from your address to another via the standard transfer and transferFrom methods.
- `transferFrom` requires you to set an allowance first (or use EIP-2612 permit).

**2.2 Balances and Allowances**
- Query balances using `balanceOf(address)`
- Query allowances using `allowance(address,address)`
- Increase or decrease allowances using `approve`, `increaseAllowance`, or `decreaseAllowance`.

### 3. Issuer System

Issuers are special addresses authorized to mint new tokens (up to certain limits) and burn existing tokens. The purpose is to manage token supply under specific conditions.

**3.1 Becoming an Issuer**
- `authorizeIssuer(address newIssuer)`
  - Public function (anyone can call it) that authorizes `newIssuer` to become an issuer, provided:
    - `newIssuer` is not already authorized.
    - Total issuer count has not reached `maxIssuers`.
  - Once authorized, the new issuer appears in the issuers array and has special privileges (mint/burn).
  - This function is modified by `cooldown` which checks that the address submitted doesn't have an active cooldown.

**3.2 Losing Issuer Status**
- `deauthorizeIssuer(address existingIssuer)`
  - Public function that deauthorizes an existing issuer if:
    1. The issuer’s authorization has expired or
	  2. The issuer itself calls this function (self-deauthorization).
  - Once deauthorized, the address is removed from the issuers array and loses mint/burn rights.
  - This function contains logic pertaining to the `cooldown` modifier.  If an issuer self-deauthorizes prior to serving 95% of the `issuerInterval` since they were last authorized, their cooldown will be set to the block number + the remaining number of blocks until their original expiration value.  This is to prevent issuers from abusing self-deauthorization to attempt to circumvent the contract's minting logic.
- `deauthorizeAllExpiredIssuers()`
  - Loops through all issuers and automatically removes any that are expired.

**3.3 Expiration Logic**
- Each issuer has an `expirationBlock`. The default “term” for an issuer is `issuerInterval` blocks.
- If the current block is beyond an issuer’s `expirationBlock`, that issuer is considered expired and cannot mint or burn.

**3.4 Transferring Issuer Authorization**
- `transferIssuerAuthorization(address newIssuer)`
  - Allows an existing (non-expired) issuer to transfer its issuer status to a new address.
  - The old issuer’s data (like total minted, burn counts, etc.) is copied to the new address, but the old issuer is deauthorized.
  - This function is modified by `cooldown` which checks that the address submitted doesn't have an active cooldown.
  - Transfer conditions:
    - `msg.sender` must be an existing issuer whose term has not expired.
    - `newIssuer` must not already be an issuer.
    - `newIssuer` can’t be `address(0)` or the token contract address.

**3.5 Issuer Data Structure**

```
struct Issuer {
    uint256 index;
    uint256 startingBlock;
    uint256 expirationBlock;
    uint256 totalMinted;
    uint256 mintCount;
    uint256 burnCount;
    uint256 totalBurned;
}
```

Each issuer has:
- `index`: An index in the issuers array.
- `startingBlock`: The block at which they were initially authorized.
- `expirationBlock`: The block after which they’re considered expired.
- `totalMinted` / `totalBurned`: How many tokens they’ve minted/burned.
- `mintCount` / `burnCount`: How many times they’ve minted/burned.

### 4. Minting Tokens

- `mint(address to, uint256 userRequestedAmount)` (only callable by non-expired issuers)
	1.	If `totalSupply() == 0`, the contract forces the minted amount to minSupply, ignoring userRequestedAmount.
	2.	Otherwise, the contract checks that `userRequestedAmount > 0` and does not exceed `currentSupply * mintFactor / 10000`.
	3.	If `currentSupply < minSupply`, a shortfall is automatically added to meet `minSupply`.
	4.	Finally, tokens are minted to `to`.

**Important Note:**  Because token balances are calculated to 18 decimal places, you must pad the amount of tokens you intend to mint with 18 zeroes.  For example, to mint 500 PDoT, you would enter `500000000000000000000` (ie 500 * 10**18) as the `userRequestedAmount` parameter when calling the function.  The same is also true for transferring and burning tokens.

**Key Points:**
- Only an authorized, non-expired issuer can call mint.
- If supply is zero, the minted amount is exactly `minSupply`.
- Otherwise, the issuer can only mint up to a fraction (up to `baseMintFactor / 10**4`) of the current supply, with additional dynamic logic to adjust that factor.  This logic is implemented by the internal helper function `calculateMintFactor()`.
- Users can find the current mint factor of a specific issuer by calling the public getter function: `getIssuerMintFactor(address _issuerAddress)`.

### 5. Burning Tokens

Issuers can burn tokens:

1.`burn(uint256 amount)`
  - Burns tokens from the issuer’s own balance.

2.`burnFrom(address account, uint256 amount)`
  - Burns tokens from account, provided the issuer has enough allowance from that account.

Both functions update the issuer’s `totalBurned` and `burnCount`.

### 6. Constants

The contract utilizes four constants:
- `maxIssuers` = 1000
  - Hard-coded cap on the total number of authorized issuers allowed at any time.
- `issuerInterval` = 2628000
  - The standard issuer authorization period expressed in blocks.  Assumes 12s per block for a term period of roughly one year.
- `baseMintFactor` = 500
  - Hard-coded cap on the amount of tokens an issuer can mint in one function call, expressed as a percentage of the current total supply with 10**4 scaling applied for accuracy.  `baseMintFactor` is adjusted based on the issuer's mint and burn history to determine the issuer's actual mint factor.
- `minSupply` = 1000000 * 10**18
  - Hard-coded supply floor.  If the current total supply ever dips below `minSupply`, the next issuer to mint will automatically mint enough tokens to bring the total supply back to the floor.

  **Note:** In the edge case that the current total supply is 0, such as immediately after contract deployment, the first issuer to mint will automatically mint the full value of `minSupply`, which prevents the contract from bricking due to conflicting logic checks.

### 7. Interface

The smart contract implements the interface `IPublicDomainToken` which itself inherits the functionality of `IERC20`, `IERC20Permit`, and `IVotes`.  This makes `IPublicDomainToken` a one-stop-shop for most of the token's broad functionality.

**Note:** `burn()` and `burnFrom()` are exposed by `IERC20` and inherited by `IPublicDomainToken`.

### 8. ERC20 Permit and Votes

- `ERC20Permit` allows gasless approvals using EIP-2612. Users can sign a permit message off-chain, and another account can submit the signed message on-chain to set allowances without spending ETH for the approval transaction.
- `ERC20Votes` adds voting/polling capabilities typically used in governance systems. Each token holder can delegate votes or vote with their tokens.

### 9. Testing

Tested using Foundry.  See `PublicDomainToken.t.sol` for coverage of issuer flows, minting, burning, and event emission checks.

### 10. License

The `PublicDomainToken.sol` file is published under the MIT License (see the SPDX header). Please see the `LICENSE` file in this repo for more details.

### 11. Frequently Asked Questions

**1. Who can call `authorizeIssuer`?**
  - Anyone can call it, but the contract reverts if the address is already authorized or if `maxIssuers` is reached.

**2. Why does the contract force `minSupply` on first mint?**
  - It ensures there’s a baseline liquidity of tokens whenever the supply is zero.

**3. What happens if an issuer’s term expires?**
  - The issuer can no longer call mint or burn. They can be deauthorized by anyone calling `deauthorizeIssuer(issuer)` or automatically by `deauthorizeAllExpiredIssuers()`.

**4. Does the contract owner automatically become an issuer?**
  - No, being the owner does not make you an issuer by default. The owner can adjust parameters but must explicitly authorize themselves if they want to mint/burn.

**5. Can users see who is an issuer?**
  - Yes, the contract exposes an array of all issuers, plus you can query `isIssuer(address)`.

**6. How much can an issuer mint?**
  - The amount that an issuer can mint in one call is capped at `baseMintFactor` as a percentage value of the current supply.  However, the mint function also calculates a personal mint factor for each issuer at the time of minting which limits how many tokens they can mint at that time.  This mint factor is determined by how much the issuer has previously minted vs how much they have burned.

**7. Will you deploy DEX liquidity for Public Domain Token?**
  - I will not be deploying a liquidity pool. Whether or not anyone decides to seed a pool for the token is entirely up to individual token holders and issuers.

**8. Will you deploy a governor contract for Public Domain Token?**
  - No, the token parameters are intended to be ungovernable.  If someone wants to use Public Domain Token as their governance token, that is their decision, and they can deploy their own governor contract to do so.

**9. Does Public Domain Token have an official Discord or Telegram channel?**
  - There are no official social media channels for Public Domain Token.  This includes Discord, X, Farcaster, and Telegram.  Individuals are free to create their own communities around the token as they wish, but be wary of anyone claiming to officially represent Public Domain Token.  And if anyone claims to be actively developing Public Domain Token itself (and not a derivative), they're almost certainly trying to scam you.

### 12. Summary

- `Public Domain Token` (PDoT) is an ERC20 token with custom issuance mechanics managed by authorized issuers who have time-limited mint/burn privileges.
- Issuers can be added or removed, ensuring flexible but controlled supply management.
- Users enjoy standard ERC20 features, plus gasless approvals (Permit) and voting capabilities (Votes).

### Additional Resources

- **OpenZeppelin Functions:** You can explore the contract code directly or consult developer docs (https://docs.openzeppelin.com/) for `ERC20`, `ERC20Permit`, and `ERC20Votes`.

Use this document as a quick reference to understand how the token supply mechanics and issuer system work.