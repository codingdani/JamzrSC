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
        address _tokenContract, 
        uint256 _tokenId, 
        uint256 _price, 
        uint256 _quantity
        ) external returns (uint256 listingId) {
        require(supportedTokenContracts[_tokenContract], 
        "Token contract not supported");
        require(IERC1155(_tokenContract).balanceOf(msg.sender, _tokenId) >= _quantity, 
        "Insufficient token balance");
        listingId = nextListingId++;
        listings[listingId] = Listing(msg.sender, _tokenContract, _tokenId, _price, _quantity, true);
        sellerListings[msg.sender].push(listingId);
        assignTokenToListings[_tokenContract][_tokenId].push(listingId);
        activeListings.push(listingId);
        listingIndex[listingId] = activeListings.length - 1;
        IERC1155(_tokenContract).safeTransferFrom(msg.sender, address(this), _tokenId, _quantity, "");
        emit ListingCreated(listingId, msg.sender, _tokenContract, _tokenId, _price, _quantity);
        return listingId;
    }

    function cancelListing(uint256 _listingId) external {
        Listing storage listing = listings[_listingId];
        require(listing.seller == msg.sender, "Not the seller");
        require(listing.isActive, "Listing not active");
        listing.isActive = false;
        IERC1155(listing.tokenContract)
        .safeTransferFrom(address(this), msg.sender, listing.tokenId, listing.quantity, "");
        _removeFromActiveListings(_listingId);
        emit ListingCancelled(_listingId);
    }

    function buyNFT(uint256 _listingId, uint256 _quantity) external payable nonReentrant {
        Listing storage listing = listings[_listingId];
        require(listing.isActive, "Listing not active");
        require(_quantity <= listing.quantity, "Insufficient quantity available");
        uint256 totalPrice = listing.price * _quantity;
        require(msg.value >= totalPrice, "Insufficient payment");
        uint256 fee = (totalPrice * marketplaceFeePercentage) / 10000;
        uint256 sellerPayment = totalPrice - fee;
    // Update state
        listing.quantity -= _quantity;
        if (listing.quantity == 0) {
            listing.isActive = false;
            _removeFromActiveListings(_listingId);
        }
    // Record transaction
        listingTransactions[_listingId].push(Transaction(
            _listingId, 
            msg.sender, 
            listing.price, 
            _quantity, 
            block.timestamp
        ));
    // Perform transfers
        bool success = payable(listing.seller).send(sellerPayment);
        require(success, "Transfer to seller failed");
        success = payable(owner).send(fee);
        require(success, "Transfer of fee failed");
        IERC1155(listing.tokenContract)
        .safeTransferFrom(address(this), msg.sender, listing.tokenId, _quantity, "");
        emit NFTPurchased(_listingId, msg.sender, _quantity);
    // Refund excess payment
        if (msg.value > totalPrice) {
            payable(msg.sender).transfer(msg.value - totalPrice);
        }
    }

    function setMarketplaceFee(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 10000, "Fee percentage cannot exceed 100%");
    //fee shown is 100.00% a 5 percent fee would be 500//
        marketplaceFeePercentage = _newFeePercentage;
        emit MarketplaceFeeUpdated(_newFeePercentage);
    }

    function getListingDetails(uint256 _listingId) external view returns (
        address seller, 
        address tokenContract,
        uint256 tokenId, 
        uint256 price, 
        uint256 quantity) {
        Listing storage listing = listings[_listingId];
        return (listing.seller, listing.tokenContract, listing.tokenId, listing.price, listing.quantity);
    }

    function _removeFromActiveListings(uint256 _listingId) internal {
    //puts specific Listing at the end of activeListings Array and trims it off the end//
    //swap of indexes because of time efficiency O(1)//
        uint256 index = listingIndex[_listingId];
        uint256 lastIndex = activeListings.length - 1;
        uint256 lastListingId = activeListings[lastIndex];
        activeListings[index] = lastListingId;
        listingIndex[lastListingId] = index;
        activeListings.pop();
        delete listingIndex[_listingId];
    }

    function addSupportedTokenContract(address _tokenContract) external onlyOwner {
        supportedTokenContracts[_tokenContract] = true;
    }

    function removeSupportedTokenContract(address _tokenContract) external onlyOwner {
        supportedTokenContracts[_tokenContract] = false;
    }
}