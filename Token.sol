// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract CustomERC1155WithRoyalties is ERC1155, Ownable, Initializable {
    using Strings for uint256;

    // Mapping from token ID to metadata URI
    mapping(uint256 => string) private _tokenURIs;

    // Mapping from token ID to royalty information
    mapping(uint256 => RoyaltyInfo) private _royalties;

    struct RoyaltyInfo {
        address recipient;
        uint256 percentage;
    }

    constructor(string memory uri) ERC1155(uri) {}

    // Function to mint new token
    // calls internal _mint Function of ERC-1155 and sets URI of new Token-ID
    function mint(
        address account, 
        uint256 id, 
        uint256 amount, 
        string memory newuri, 
        bytes memory data
        ) public onlyOwner {
        _mint(account, id, amount, data);
        setTokenURI(id, newuri);
    }

    // Function to mint batch of tokens
    function mintBatch(
        address to, 
        uint256[] memory ids, 
        uint256[] memory amounts, 
        bytes memory data
        ) public onlyOwner {
        _mintBatch(to, ids, amounts, data);
    }

    // Function to set royalties for a specific token
    function setTokenRoyalty(
        uint256 tokenId, 
        address recipient, 
        uint256 percentage
        ) public onlyOwner {
        require(percentage <= 10000, "Royalty percentage cannot exceed 100%");
        _royalties[tokenId] = RoyaltyInfo(recipient, percentage);
    }

    // Function to get royalty information for a token
    function royaltyInfo(
        uint256 tokenId, 
        uint256 salePrice
        ) public view returns (
            address receiver, 
            uint256 royaltyAmount
            ) {
        RoyaltyInfo memory royalty = _royalties[tokenId];
        return (royalty.recipient, (salePrice * royalty.percentage) / 10000);
    }

    // Function to set token URI
    /**
     * @dev Sets the metadata URI for a specific token.
     * @param id The token ID for which to set the URI.
     * @param newuri The new URI for the token's metadata.
     */
    function setTokenURI(uint256 tokenId, string memory newuri) private {
        _tokenURIs[tokenId] = newuri;
    }

    // Override URI function to return token-specific URI if set
    function uri(uint256 tokenId) public view virtual override 
    returns (string memory) {
        string memory tokenURI = _tokenURIs[tokenId];
        if (bytes(tokenURI).length > 0) {
            return tokenURI;
        }
        return super.uri(tokenId);
    }
}