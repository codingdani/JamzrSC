// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTMarketplace is ERC1155Holder, ReentrancyGuard, Ownable {
//ZU BEACHTEN: 
// Alle Käufer sollen gleiche Gas Fees zahlen (der letzte Käufer soll nicht alle state changes zahlen müssen)
// Der Marketplace ist jetzt nur Operator. Die Token werden im Wallet der Besitzer gelassen 
// Cleanup von inActive Listings sollte vom Ersteller übernommen werden => welche Funktionen braucht man wirklich? Sollten alle beibehalten werden?

    struct Listing {
        address tokenContract;
        address seller;
        uint256 tokenId;
        uint256 price;
        uint256 quantity;
        bool isActive;
    }
    //maps listindId to Listing
    mapping(uint256 => Listing) public listings;
    uint256 private nextListingId;

    uint256[] public activeListings;
    //maps listingId to index in activeListings
    mapping(uint256 => uint256) public listingIndex;
    //maps sellerAddress to Array of listingId
    mapping(address => uint256[]) public sellerListings;
    //maps tokenContractAddress to TokenId to Array of listingId
    mapping(address => mapping(uint256 => uint256[])) public assignTokenToListings;
    //maps listingId to bool to indicate that Listing needs to be removed from all mappings
    mapping(uint256 => bool) public listingNeedsCleanup;

    struct Transaction {
        uint256 listingId;
        address buyer;
        uint256 price;
        uint256 mfee;
        uint256 quantity;
        uint256 timestamp;
    }
    //maps listingId to Array of Transactions
    mapping(uint256 => Transaction[]) public listingTransactions;

    mapping(address => bool) public supportedTokenContracts;
    uint256 public marketplaceFeePercentage;

    event ListingCreated(
        uint256 indexed listingId, 
        address tokenContract,
        address indexed seller, 
        uint256 tokenId, 
        uint256 price, 
        uint256 quantity
        );
    event ListingDeactivated(uint256 indexed listingId);
    event ListingDeleted(uint256 indexed listingId);

    event NFTPurchased(uint256 indexed listingId, address indexed buyer, uint256 quantity);
    event TokenSold(
        uint256 indexed listingId, 
        address indexed tokenContract, 
        address indexed seller, 
        address buyer, 
        uint256 tokenId, 
        uint256 quantity, 
        uint256 price
        );
    event MarketplaceFeeUpdated(uint256 newFeePercentage);

    constructor(uint256 _initialFeePercentage) {
        marketplaceFeePercentage = _initialFeePercentage;
        owner = msg.sender;
    }


//All Listing Operations: create, getDetails, delete, removeFromMappings, deactivate, cleanupState

    function createListing(address _tokenContract, uint256 _tokenId, uint256 _price, uint256 _quantity) public {
        require(supportedTokenContracts[_tokenContract], "Token contract not supported");    
        require(IERC1155(_tokenContract).balanceOf(msg.sender, _tokenId) >= _quantity, "Insufficient token balance");
    //marketplace has to be set as Operator in Token-Smart-Contract via setApprovalForAll()-Function 
        require(IERC1155(_tokenContract).isApprovedForAll(msg.sender, address(this)), "Contract not approved as operator");
        uint256 listingId = nextListingId++;
        listings[listingId] = Listing(_tokenContract, msg.sender, _tokenId, _price, _quantity, true);
        sellerListings[msg.sender].push(listingId);
        activeListings.push(listingId);
        assignTokenToListings[_tokenContract][_tokenId].push(listingId);
        listingIndex[listingId] = activeListings.length - 1;
        emit ListingCreated(listingId, _tokenContract, msg.sender, _tokenId, _amount, _price);
        return listingId;
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

    function deleteListing(uint256 _listingId) external {
        Listing storage listing = listings[_listingId];
        require(listing.seller == msg.sender, "Not the seller");
        _removeFromActiveListings(_listingId);
        _removeFromSellerListings(listing.seller, _listingId);
        _removeFromAssignTokenToListings(listing.tokenContract, listing.tokenId, _listingId);
        delete listings[_listingId];
        emit ListingDeleted(_listingId);
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

    function _removeFromSellerListings(address _seller, uint256 _listingId) internal {
        uint256[] storage sellerListingIds = sellerListings[_seller];
        for (uint i = 0; i < sellerListingIds.length; i++) {
            if (sellerListingIds[i] == _listingId) {
                sellerListingIds[i] = sellerListingIds[sellerListingIds.length - 1];
                sellerListingIds.pop();
                break;
            }
        }
    }

    function _removeFromAssignTokenToListings(address _tokenContract, uint256 _tokenId, uint256 _listingId) internal {
        uint256[] storage tokenListings = assignTokenToListings[_tokenContract][_tokenId];
        for (uint i = 0; i < tokenListings.length; i++) {
            if (tokenListings[i] == _listingId) {
                tokenListings[i] = tokenListings[tokenListings.length - 1];
                tokenListings.pop();
                break;
            }
        }
    }

    function _deactivateListing(uint256 _listingId) internal {
    //should this function be included into buyNFT()-Function? Will increase gas fees for last buyer
        require(listing.isActive, "Listing already deactivated");
        Listing storage listing = listings[_listingId];
        listing.isActive = false;
        _removeFromActiveListings(_listingId);
        listingNeedsCleanup[_listingId] = true;
        emit ListingDeactivated(_listingId);
    }

    function cleanupListingState(uint256 _listingId) external {
    //only needs to exist when _deactivateListing is included into buyNFT Function
    //should be called by listing.seller or a reward could be included for all Users to collect after cleaning 
        require(listingNeedsCleanup[_listingId], "Listing doesn't need cleanup");
        Listing storage listing = listings[_listingId];
        _removeFromSellerListings(listing.seller, _listingId);
        _removeFromAssignTokenToListings(listing.tokenContract, listing.tokenId, _listingId);
        delete listingNeedsCleanup[_listingId];
    }


//Purchase NFT Function
// no state updating so the last buyer does not get punished with high gas fees
    function buyNFT(uint256 _listingId, uint256 _quantity) external payable nonReentrant {
        Listing storage listing = listings[_listingId];
        require(listing.isActive, "Listing not active");
        require(_quantity <= listing.quantity, "Insufficient quantity available");
        uint256 totalPrice = listing.price * _quantity;
        require(msg.value >= totalPrice, "Insufficient payment");
        uint256 fee = (totalPrice * marketplaceFeePercentage) / 10000;
        uint256 sellerPayment = totalPrice - fee;
    // Perform transfers
        bool success = payable(listing.seller).send(sellerPayment);
        require(success, "Transfer to seller failed");
        success = payable(owner).send(fee);
        require(success, "Transfer of fee failed");
        IERC1155(listing.tokenContract)
        .safeTransferFrom(address(this), msg.sender, listing.tokenId, _quantity, "");
    // record transaction    
        listingTransactions[_listingId].push(Transaction(
            _listingId, 
            msg.sender, 
            listing.price,
            fee, 
            _quantity, 
            block.timestamp
        ));
        emit NFTPurchased(_listingId, msg.sender, _quantity);
    }


//Marketplace Functions
    function setMarketplaceFee(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 10000, "Fee percentage cannot exceed 100%");
    //fee shown is 100.00% a 5 percent fee would be 500//
        marketplaceFeePercentage = _newFeePercentage;
        emit MarketplaceFeeUpdated(_newFeePercentage);
    }

    function addSupportedTokenContract(address _tokenContract) external onlyOwner {
        supportedTokenContracts[_tokenContract] = true;
    }

    function removeSupportedTokenContract(address _tokenContract) external onlyOwner {
        supportedTokenContracts[_tokenContract] = false;
    }
}