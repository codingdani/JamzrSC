// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTMarketplace is ERC1155Holder, ReentrancyGuard, Ownable {
    struct Listing {
        address seller;
        address tokenContract;
        uint256 tokenId;
        uint256 price;
        uint256 quantity;
        bool isActive;
    }
    mapping(uint256 => Listing) public listings;
    uint256 private nextListingId;

    uint256[] public activeListings;
    mapping(uint256 => uint256) public listingIndex;

    mapping(address => uint256[]) public sellerListings;
    mapping(address => mapping(uint256 => uint256[])) public assignTokenToListings;

    struct Transaction {
        uint256 listingId;
        address buyer;
        uint256 price;
        uint256 quantity;
        uint256 timestamp;
    }

    mapping(uint256 => Transaction[]) public listingTransactions;
    mapping(address => bool) public supportedTokenContracts;
    uint256 public marketplaceFeePercentage;

    event ListingCreated(
        uint256 indexed listingId, 
        address indexed seller, 
        address tokenContract,
         uint256 tokenId, 
         uint256 price, 
         uint256 quantity
         );
    event ListingCancelled(uint256 indexed listingId);
    event NFTPurchased(uint256 indexed listingId, address indexed buyer, uint256 quantity);
    event MarketplaceFeeUpdated(uint256 newFeePercentage);

    constructor(uint256 _initialFeePercentage) {
        marketplaceFeePercentage = _initialFeePercentage;
        owner = msg.sender;
    }

    function createListing(
        address tokenContract, 
        uint256 tokenId, 
        uint256 price, 
        uint256 quantity
        ) external returns (uint256 listingId) {
        require(supportedTokenContracts[tokenContract], 
        "Token contract not supported");
        require(IERC1155(tokenContract).balanceOf(msg.sender, tokenId) >= quantity, 
        "Insufficient token balance");
        listingId = nextListingId++;
        listings[listingId] = Listing(msg.sender, tokenContract, tokenId, price, quantity, true);
        sellerListings[msg.sender].push(listingId);
        assignTokenToListings[tokenContract][tokenId].push(listingId);
        activeListings.push(listingId);
        listingIndex[listingId] = activeListings.length - 1;
        IERC1155(tokenContract).safeTransferFrom(msg.sender, address(this), tokenId, quantity, "");
        emit ListingCreated(listingId, msg.sender, tokenContract, tokenId, price, quantity);
        return listingId;
    }

    function cancelListing(uint256 listingId) external {
        Listing storage listing = listings[listingId];
        require(listing.seller == msg.sender, "Not the seller");
        require(listing.isActive, "Listing not active");
        listing.isActive = false;
        IERC1155(listing.tokenContract)
        .safeTransferFrom(address(this), msg.sender, listing.tokenId, listing.quantity, "");
        _removeFromActiveListings(listingId);
        emit ListingCancelled(listingId);
    }

    function buyNFT(uint256 listingId, uint256 quantity) external payable nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.isActive, "Listing not active");
        require(quantity <= listing.quantity, "Insufficient quantity available");
        require(msg.value >= listing.price * quantity, "Insufficient payment");
        uint256 totalPrice = listing.price * quantity;
        uint256 fee = (totalPrice * marketplaceFeePercentage) / 10000;
        uint256 sellerPayment = totalPrice - fee;
        listing.quantity -= quantity;
        if (listing.quantity == 0) {
            listing.isActive = false;
            _removeFromActiveListings(listingId);
        }

        IERC1155(listing.tokenContract).safeTransferFrom(address(this), msg.sender, listing.tokenId, quantity, "");
        payable(listing.seller).transfer(sellerPayment);
        payable(owner).transfer(fee);
        Transaction memory newTransaction = Transaction(listingId, msg.sender, listing.price, quantity, block.timestamp);
        listingTransactions[listingId].push(newTransaction);
        emit NFTPurchased(listingId, msg.sender, quantity);
    }

    function setMarketplaceFee(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= 10000, "Fee percentage cannot exceed 100%");
        marketplaceFeePercentage = newFeePercentage;
        emit MarketplaceFeeUpdated(newFeePercentage);
    }

    function getListingDetails(uint256 listingId) external view returns (
        address seller, 
        address tokenContract,
        uint256 tokenId, 
        uint256 price, 
        uint256 quantity) {
        Listing storage listing = listings[listingId];
        return (listing.seller, listing.tokenContract, listing.tokenId, listing.price, listing.quantity);
    }

    function _removeFromActiveListings(uint256 listingId) internal {
        uint256 index = listingIndex[listingId];
        uint256 lastIndex = activeListings.length - 1;
        uint256 lastListingId = activeListings[lastIndex];
        activeListings[index] = lastListingId;
        listingIndex[lastListingId] = index;
        activeListings.pop();
        delete listingIndex[listingId];
    }

    function addSupportedTokenContract(address tokenContract) external onlyOwner {
        supportedTokenContracts[tokenContract] = true;
    }

    function removeSupportedTokenContract(address tokenContract) external onlyOwner {
        supportedTokenContracts[tokenContract] = false;
    }
}