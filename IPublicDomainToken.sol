// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPublicDomainToken is IERC20{

    event IssuerAuthorized(address indexed issuer, uint256 expirationBlock);
    event IssuerDeauthorized(address indexed issuer, address indexed deauthorizer);
    event IssuerActivity(
        address indexed issuer,
        uint256 minted,
        uint256 burned,
        uint256 totalMintedSoFar,
        uint256 totalBurnedSoFar
    );

    /**
     * @dev Authorizes `newIssuer` as an issuer if not already authorized,
     *      as long as totalIssuers < maxIssuers.
     */
    function authorizeIssuer(address newIssuer) external;

    /**
     * @dev Deauthorizes `existingIssuer` if its expirationBlock
     *      is in the past.
     */
    function deauthorizeIssuer(address existingIssuer) external;

    /**
     * @dev Deauthorizes any addresses in the issuers array
     *      whose expiration has passed.
     */
    function deauthorizeAllExpiredIssuers() external;

    /**
     * @dev Returns the entire array of issuers.
     */
    function getIssuers() external view returns (address[] memory);

    /**
     * @dev Mints tokens to address `to`, subject to the mint factor logic.
     */
    function mint(address to, uint256 userRequestedAmount) external;

    /**
     * @dev Burns tokens from the caller (must be issuer).
     */
    function burn(uint256 amount) external;

    /**
     * @dev Burns tokens from `account`, using allowance logic.
     */
    function burnFrom(address account, uint256 amount) external;

    /**
     * @dev Returns the current computed mint factor for a given `_issuerAddress`.
     */
    function getIssuerMintFactor(address _issuerAddress) external view returns (uint256);
}
