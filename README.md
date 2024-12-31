# public-domain-token
## context
An open ERC20 token with public permissioned minting.

Usually when someone launches an ERC20 token, if the total capped supply is not minted during contract deployment, issuance will be generated via staking, mining, or direct manual minting through a governance contract.  In most cases, issuance is controlled by one party, even if that party abdicates their control after issuance has completed.  In these instances, the token is usually issued for a specific purpose, whether to facilitate governance over a specific DAO or on-chain product, to serve as a medium of exchange for a specific product, etc.  And in most cases, the token issuer is usually a stakeholder in whatever the token utility is intended to be.

I thought it would be an interesting experiment to deploy a token with a dynamic that I hope will contrast the typical token approach.  Instead of having a single issuer, this token has multiple potential issuers based on an authorized issuer list.  The issuer list is completely open and permissionless save for a hard cap to the number of authorized issuers at any given time.  So any address can authorize itself as an issuer as long as the cap has not been reached.

Issuers have the ability to mint tokens and burn tokens as long as their address is still authorized.  Authorization expires after roughly 1 year, assuming 12s per block.  Issuers have the ability to mint an arbitrary number of tokens and may mint an arbitrary number of times while their address is authorized.  However, the amount of tokens they can mint is limited by hardcoded minting logic based on a base factor relative to the total supply of the token.  This factor is then influenced by data that is specific to each issuer, namely how many tokens they have minted, how often they mint, how many tokens they have burned, and how often they burn - all over the duration of their current issuer authorization.  The more an issuer mints, the less tokens they will be able to mint in the future.  However, this can be offset by burning tokens.  It's up to issuers to decide what ratio of minting to burning best suits their purposes.

After deployment, the ownership of the contract will be transferred to itself.  None of the contract paramaters will be governable.  The operation of the contract will be entirely autonomous and deterministic based on the existing deployed code.  However, the token is built off of OpenZeppelin's contract libraries including `ERC20Burnable`, `ERC20Permit`, `Ownable`, and `ERC20Votes`.  Hopefully this gives the token a wide range of potential utility such that issuers can chose to use the token for a number of different purposes.

In an ideal world, anyone can use the token for anything, as long as they consider the fact that they will not be the only authorized issuer at any given time.  This introduces some interesting new areas for experimentation and game theory.  Will issuers coordinate and collaborate to maintain the health of the token ecosystem and all of the various connected stakeholders?  Or will the issuer ecosystem quickly devolve into pure PvP?

## documentation

### 1. Overview
- **Name:** Public Domain Token
- **Symbol:** PDoT
- **Token Standard:** ERC20 (with additional capabilities)
- **Core Features:**
  - Standard ERC20 transfers.
  - ERC20Permit (gasless approvals).
  - ERC20Votes (voting/polling capabilities).
  - Burnable by authorized issuers.
  - Special “issuer” system for minting and burning tokens.

**Important:** The contract has additional controls and logic that differ from a typical ERC20:
	1.	Min Supply: If total supply is 0, the first mint automatically brings supply up to a minimum threshold.
	2.	Issuers: Certain authorized addresses can mint/burn under constraints.
	3.	Owner: The contract has a single owner who can adjust certain parameters (like intervals, min supply, etc.).

### 2. Basic ERC20 Functionality

2.1 Transferring Tokens
	•	Like any ERC20, you can send tokens from your address to another via the standard transfer and transferFrom methods.
	•	transferFrom requires you to set an allowance first (or use EIP-2612 permit).

2.2 Balances and Allowances
	•	Query balances using balanceOf(address)
	•	Query allowances using allowance(address,address)
	•	Increase or decrease allowances using approve, increaseAllowance, or decreaseAllowance.

### 3. Issuer System

Issuers are special addresses authorized to mint new tokens (up to certain limits) and burn existing tokens. The purpose is to manage token supply under specific conditions.

3.1 Becoming an Issuer
	•	authorizeIssuer(address newIssuer)
	•	Public function (anyone can call it) that authorizes newIssuer to become an issuer, provided:
	•	newIssuer is not already authorized.
	•	Total issuer count has not reached maxIssuers.
	•	Once authorized, the new issuer appears in the issuers array and has special privileges (mint/burn).

3.2 Losing Issuer Status
	•	deauthorizeIssuer(address existingIssuer)
	•	Public function that deauthorizes an existing issuer if:
	1.	The issuer’s authorization has expired or
	2.	The issuer itself calls this function (self-deauthorization).
	•	Once deauthorized, the address is removed from the issuers array and loses mint/burn rights.
	•	deauthorizeAllExpiredIssuers()
	•	Loops through all issuers and automatically removes any that are expired.

3.3 Transferring Issuer Authorization
	•	transferIssuerAuthorization(address newIssuer)
	•	Allows an existing (non-expired) issuer to transfer its issuer status to a new address.
	•	The old issuer’s data (like total minted, burn counts, etc.) is copied to the new address, but the old issuer is deauthorized.
	•	Transfer conditions:
	•	newIssuer must not already be an issuer.
	•	newIssuer can’t be address(0) or the token contract address.
	•	The old issuer must still be unexpired.

3.4 Expiration Logic
	•	Each issuer has an expirationBlock. The default “term” for an issuer is issuerInterval blocks.
	•	If the current block is beyond an issuer’s expirationBlock, that issuer is considered expired and cannot mint or burn.
	•	The owner can set issuerInterval (for testing or dynamic changes).

### 4. Minting Tokens
	•	mint(address to, uint256 userRequestedAmount) (only callable by non-expired issuers)
	1.	If totalSupply() == 0, the contract forces the minted amount to minSupply, ignoring userRequestedAmount.
	2.	Otherwise, the contract checks that userRequestedAmount > 0 and does not exceed (currentSupply * mintFactor) / 100.
	3.	If currentSupply < minSupply, a shortfall is automatically added to meet minSupply.
	4.	Finally, tokens are minted to to.

Key Points:
	•	Only an authorized, non-expired issuer can call mint.
	•	If supply is zero, the minted amount is exactly minSupply.
	•	Otherwise, the issuer can only mint up to a fraction (up to baseMintFactor%) of the current supply, with additional dynamic logic to adjust that factor.

### 5. Burning Tokens

Issuers can burn tokens:
	1.	burn(uint256 amount)
	•	Burns tokens from the issuer’s own balance.
	2.	burnFrom(address account, uint256 amount)
	•	Burns tokens from account, provided the issuer has enough allowance from that account.

Both functions update the issuer’s totalBurned and burnCount.

### 6. Owner-Only Settings
	1.	setIssuerInterval(uint newInterval)
	•	Updates the block-based “term” for new issuers. (For instance, 2,628,000 blocks ~ 1 year at 12s/block.)
	2.	setBaseMintFactor(uint newMintFactor)
	•	Changes the base percentage limit (like 5%) for how much an issuer can mint relative to supply.
	3.	setMinSupply(uint256 newMinSupply)
	•	Changes the minimum supply enforced when the supply is zero.

	Note: The contract comments suggest these setters are only for testing and ideally removed before production, or at least restricted to the owner only.

### 7. ERC20 Permit and Votes
	•	ERC20Permit allows gasless approvals using EIP-2612. Users can sign a permit message off-chain, and another account can submit the signed message on-chain to set allowances without spending ETH for the approval transaction.
	•	ERC20Votes adds voting/polling capabilities typically used in governance systems. Each token holder can delegate votes or vote with their tokens.

### 8. Frequently Asked Questions
	1.	Who can call authorizeIssuer?
Anyone can call it, but the contract reverts if the address is already authorized or if maxIssuers is reached.
	2.	Why does the contract force minSupply on first mint?
It ensures there’s a baseline liquidity of tokens whenever the supply is zero.
	3.	What happens if an issuer’s term expires?
The issuer can no longer call mint or burn. They can be deauthorized by anyone calling deauthorizeIssuer(issuer) or automatically by deauthorizeAllExpiredIssuers().
	4.	Does the contract owner automatically become an issuer?
No, being the owner does not make you an issuer by default. The owner can adjust parameters but must explicitly authorize themselves if they want to mint/burn.
	5.	Can users see who is an issuer?
Yes, the contract exposes an array of all issuers, plus you can query isIssuer(address).

### 9. Summary
	•	PublicDomainToken (PDoT) is an ERC20 token with custom issuance mechanics managed by authorized issuers who have time-limited mint/burn privileges.
	•	Issuers can be added or removed, ensuring flexible but controlled supply management.
	•	Owner can fine-tune issuer intervals, minimum supply, and base mint factors.
	•	Users enjoy standard ERC20 features, plus gasless approvals (Permit) and voting capabilities (Votes).

### Additional Resources
	•	Functions: You can explore the contract code directly or consult developer docs for ERC20, ERC20Permit, and ERC20Votes.
	•	Security: Always ensure you understand the roles and privileges of owners/issuers before engaging with the token.

Use this document as a quick reference to understand how the token supply mechanics and issuer system work.