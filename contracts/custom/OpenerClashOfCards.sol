// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../utils/Ownable.sol";

contract OpenerClashOfCards is  Ownable, ERC721 {

    using SafeMath for uint256;

    ERC20 public _purchaseToken;
    // Mapping from address to bool, if egg was already claimed
    // The hash is about the userId and the nftIds array
    mapping(address => mapping(uint256 => bool)) public registeredIDs;
    mapping(address => uint256[]) public registeredIDsArray;
    mapping(uint256 => bool) public alreadyMinted;
    mapping(uint256 => Pack) public packs;
    uint256 public packIncrementId = 0;
    uint256 public lastNFTID = 0;

    event PackCreated(uint256 packId, uint256  nftsAmount, string indexed serie, string indexed packType, string indexed drop);
    event PackOpened(address indexed by, uint256 indexed packId);
    event PackDelete(uint256 indexed packId);

    bool public _closed = false;
    uint256 public _openedPacks = 0;

    struct Pack {
        uint256 packId;
        uint256 nftAmount;
        uint256 packNumber;
        uint256 initialNFTId;
        uint256 saleStart;
        uint256[] saleDistributionAmounts;
        address[] saleDistributionAddresses;
        // Catalog info
        uint256 price; // in usd (1 = $0.000001)
        string serie;
        string drop;
        string packType;
        //external info
        address buyer;
    }

  
    constructor (string memory name, string memory symbol, ERC20 _purchaseToken) public ERC721(name, symbol) {}

    function _distributePackShares(address from, uint256 packId, uint256 amount) internal {
        //transfer of fee share
        Pack memory pack = packs[packId];

        for(uint i = 0; i < pack.saleDistributionAddresses.length; i++){
            //transfer of stake share
            _purchaseToken.transferFrom(
                from,
                pack.saleDistributionAddresses[i],
                (pack.saleDistributionAmounts[i] * amount) / 100
            );
        }
    }


    function setTokenURI(uint256 tokenId, string memory uri) public onlyOwner {
        _setTokenURI(tokenId, uri);
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        _setBaseURI(baseURI);
    }


    function exists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }
    
    function getRegisteredIDs(address _address) public view returns(uint256[] memory) {
        return registeredIDsArray[_address];
    }

    function getPackbyId(uint256 _packId) public onlyOwner returns (uint256, uint256, uint256, uint256, string memory, string memory, string memory, address, 
        address[] memory, uint256[] memory)  {
        Pack memory pack = packs[_packId];
        return (
            pack.packId, pack.packNumber, pack.initialNFTId, pack.price, pack.serie, pack.drop, pack.packType, pack.buyer,
            pack.saleDistributionAddresses, pack.saleDistributionAmounts);
    }

    function buyPack(uint256 packId) public {
        require(!_closed, "Opener is locked");
        require(packs[packId].buyer != address(0), "Pack was already bought");
        require(packs[packId].price != 0, "Pack has to exist");

        require(_purchaseToken.allowance(msg.sender, address(this)) >= packs[packId].price , "Not enough money per pack");

        address from = msg.sender;

        _distributePackShares(from, packId, packs[packId].price);

        _openedPacks += 1;

        for(uint i = 0; i < packs[packId].nftAmount; i++){
            registeredIDs[msg.sender][packs[packId].initialNFTId+i] = true;
            registeredIDsArray[msg.sender].push(i);
        }

        packs[packId].buyer = from;

        emit PackOpened(from, packId);

    }

    function createPack(uint256 packNumber, uint256 nftAmount, uint256 price, 
        string memory serie, string memory packType, string memory drop, uint256 saleStart,
        address[] memory saleDistributionAddresses,  uint256[] memory saleDistributionAmounts /* [1;98;1]*/
    ) public onlyOwner {

        require(saleDistributionAmounts.length == saleDistributionAddresses.length, "saleDistribution Lenghts are not the same");
        uint256 totalFees = 0;
        for(uint i = 0; i < saleDistributionAddresses.length; i++){
            totalFees += saleDistributionAmounts[i];
        }
        require(totalFees == 100, "Sum of all amounts has to equal 100");

        Pack memory pack = packs[packIncrementId];
        pack.packId = packIncrementId;
        pack.packNumber = packNumber;
        pack.nftAmount = nftAmount;
        pack.saleStart = saleStart;
        pack.initialNFTId = lastNFTID;
        pack.price = price;
        pack.serie = serie;
        pack.drop = drop;
        pack.saleDistributionAddresses = saleDistributionAddresses;
        pack.saleDistributionAmounts = saleDistributionAmounts;
        pack.packType = packType;

        emit PackCreated(packIncrementId, nftAmount, serie, packType, drop);
        lastNFTID = lastNFTID + nftAmount;
        packIncrementId = packIncrementId+1;
    }

     function offerPack(uint256 packId, address receivingAddress) public onlyOwner {
        require(packs[packId].packId == packId, "Pack does not exist");
        Pack memory pack = packs[packId];
        packs[packId].buyer = receivingAddress;

        _openedPacks += 1;

        for(uint i = 0; i < packs[packId].nftAmount; i++){
            registeredIDs[receivingAddress][packs[packId].initialNFTId+i] = true;
            registeredIDsArray[receivingAddress].push(i);
        }

        emit PackOpened(receivingAddress, packId);
    }

    function editPackInfo(uint256 _packId, uint256 _saleStart, string memory serie, string memory packType, string memory drop, uint256 price) public onlyOwner {
        require(block.timestamp < packs[_packId].saleStart, "Sale is already live");
        packs[_packId].saleStart = _saleStart;
        packs[_packId].serie = serie;
        packs[_packId].packType = packType;
        packs[_packId].drop = drop;
        packs[_packId].price = price;
    }

    function deletePackById(uint256 packId) public onlyOwner {
        require(block.timestamp < packs[packId].saleStart, "Sale is already live");
        delete packs[packId];
        emit PackDelete(packId);
    }

    function mint(uint256 tokenIdToMint) public {
        require(registeredIDs[msg.sender][tokenIdToMint], "Token was not registered or not the rightful owner");
        require(!alreadyMinted[tokenIdToMint], "Already minted");

        alreadyMinted[tokenIdToMint] = true;
        _safeMint(msg.sender, tokenIdToMint);
    }

    function setPurchaseTokenAddress(ERC20 purchaseToken) public onlyOwner {
        _purchaseToken = purchaseToken;
    }

    function lock() public onlyOwner {
        _closed = true;
    }

    function unlock() public onlyOwner {
        _closed = false;
    }
}