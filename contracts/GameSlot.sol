// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;                                     // Certik DCK-01

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Refer to Pancake SmartChef Contract: https://bscscan.com/address/0xCc2D359c3a99d9cfe8e6F31230142efF1C828e6D#readContract
contract GameSlot is Ownable, ReentrancyGuard, IERC721Receiver {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    IBEP20 public nativeToken;
    IBEP20 public gamePointToken;

    // The address of the manager
    address public SLOT_MANAGER;

    // Whether it is initialized
    bool public isInitialized;

    // The reserved tokens in the slot
    uint256 public reservedAmount;
    uint256 public unlockLimit;                     // GSD-03
    
    uint256 public constant MAX_PERFORMANCE_FEE = 5000; // 50%
    uint256 public performanceFee = 200; // 2%

    // Whether it is suspended
    bool public suspended = false;
    uint256 public tokenId;

    address public ownerAccount;
    address public admin;
    IERC721 public NFT;                            // The NFT token address that each game provider should hold

    // address public treasury;
    address public treasury;

    // Send funds to blacklisted addresses are not allowed
    mapping(address => bool) public blacklistAddresses;

    event AdminTokenRecovery(address indexed tokenRecovered, uint256 amount);       // Certik GSD-01
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event AddSlotEvent(uint256 indexed tokenId, address indexed gameAccount);
    event StatusChanged(address indexed slotAddress, bool suspended);
    event SlotUnlocked(address indexed user, address indexed gameAccount, uint256 amount);

    event AdminUpdated(address indexed user, address indexed admin);
    event Payout(address indexed user, address indexed receiver, uint256 amount);
    event CashoutPoints(address indexed user, uint256 amount);
    event AddToWhitelist(address indexed entry);
    event RemoveFromWhitelist(address indexed entry);
    event SetReservedAmount(uint256 amount);
    event SetPerformanceFee(uint256 amount);
    event SetUnlockLimitAmount(uint256 amount);
    event SetTreasury(address indexed amount);                                  // Certik 

    constructor(
        address _NFT,
        address _nativeToken,
        address _gamePointToken,
        uint256 _reservedAmount,
        address _manager
    ) public {
        require(_NFT != address(0), "_NFT is a zero address");                             // Certik GSD-02
        require(_nativeToken != address(0), "_nativeToken is a zero address"); 
        require(_gamePointToken != address(0), "_gamePointToken is a zero address");

        NFT = IERC721(_NFT);
        // Set manager to SlotManager rather than factory
        SLOT_MANAGER = _manager;
        nativeToken = IBEP20(_nativeToken);
        gamePointToken = IBEP20(_gamePointToken);
        reservedAmount = _reservedAmount;

        treasury = _manager;
    }

    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     *
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /*
     * @notice Initialize the contract, owner may not be the msg.sender
     * @param _tokenId: tokenId of the NFT
     * @param _owner: The current owner of NFT
     */
    function initialize(
        uint256 _tokenId,
        address _owner
    ) external {
        require(!isInitialized, "Already initialized");
        require(msg.sender == SLOT_MANAGER, "Not manager");

        tokenId = _tokenId;
        _add(_tokenId, _owner);

        // Make this contract initialized
        isInitialized = true;

        emit AddSlotEvent(_tokenId, msg.sender);
    }

    /**
     * Game provider to bid slot
     * @param _owner is the NFT owner (Game provider)
     * @param _tokenId is the token owned by owner and to be transffered into this slot
     */
    function _add(uint256 _tokenId, address _owner) private nonReentrant {
        require(NFT.ownerOf(_tokenId) != address(this), "Already owner");
        NFT.safeTransferFrom(
            _owner,
            address(this),
            _tokenId
        );
        // require(NFT.ownerOf(_tokenId) == address(this), "Not received");      // Certik GSD-09
        ownerAccount = _owner;
        // Admin account is set to same account of ownerAccount first
        admin = _owner;
    }

    /**
     * @notice This function is private and not privilege checking
     * Safe token transfer function for nativeToken, just in case if rounding error causes pool to not have enough tokens.
     */
    function safeTransfer(address _to, uint256 _amount) private {
        uint256 bal = nativeToken.balanceOf(address(this));
        if (_amount > bal) {
            nativeToken.safeTransfer(_to, bal);                     // Certik GSD-07
        } else {
            nativeToken.safeTransfer(_to, _amount);                 // Certik GSD-07
        }
    }

    /**
     * @notice This function is private and not privilege checking
     * Safe token transfer function for point token, just in case if rounding error causes pool to not have enough tokens.
     */
    function safeTransferPoints(address _to, uint256 _amount) private {
        uint256 bal = gamePointToken.balanceOf(address(this));
        if (_amount > bal) {
            gamePointToken.safeTransfer(_to, bal);                  // Certik GSD-07
        } else {
            gamePointToken.safeTransfer(_to, _amount);              // Certik GSD-07
        }
    }

    // Owner is the GameSlot, and triggered by Game Slot owner / admin
    function payout(address _to, uint256 _amount) external nonReentrant {
        require(_to != address(0), "Cannot send to 0 address");
        require(_amount > 0, "Must more than 0");
        require(!suspended, "Slot is suspended");
        require(msg.sender == admin, "Only the game admin can payout");
        require(_balance() > reservedAmount, "Balance must more than reserved");
        require(_amount <= (_balance() - reservedAmount), "Exceeded max payout-able amount");
        require(!blacklistAddresses[_to], "user is blacklisted");

        uint256 currentPerformanceFee = _amount.mul(performanceFee).div(10000);
        safeTransfer(treasury, currentPerformanceFee);
        safeTransfer(_to, _amount.sub(currentPerformanceFee));

        emit Payout(msg.sender, _to, _amount);
    }

    /**
     * @notice Owner is the GameSlot, and triggered by Game Slot owner
     * There is no theshold to cashout
     */
    function cashoutPoints(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Must more than 0");
        require(!suspended, "Slot is suspended");
        require(msg.sender == admin || msg.sender == ownerAccount, "Only the game owner or admin can cashout");
        require(_amount <= _balanceOfPoints(), "Exceeded max game points amount");

        safeTransferPoints(ownerAccount, _amount);

        emit CashoutPoints(msg.sender, _amount);
    }

    /**
     * Unlock NFT and return the slot back
     * Only return the current tokenId back to ownerAccount
     *
     * TODO: need more rules to unlock slot
     */
    function unlock() external onlyOwner {
        require(_balance() < unlockLimit, "Balance must be less than balance before unlock");     // Certik GSD-03

        NFT.transferFrom(
            address(this),
            ownerAccount,
            tokenId
        );

        isInitialized = false;

        emit SlotUnlocked(msg.sender, ownerAccount, tokenId);
    }
    
    function addToBlacklist(address[] calldata entries) external onlyOwner {
        for(uint256 i = 0; i < entries.length; i++) {
            address entry = entries[i];
            require(entry != address(0), "NULL_ADDRESS");

            blacklistAddresses[entry] = true;
            emit AddToWhitelist(entry);
        }   
    }

    function removeFromBlacklist(address[] calldata entries) external onlyOwner {
        for(uint256 i = 0; i < entries.length; i++) {
            address entry = entries[i];
            require(entry != address(0), "NULL_ADDRESS");
            
            blacklistAddresses[entry] = false;
            emit RemoveFromWhitelist(entry);
        }
    }

    /*
     * @notice Withdraw staked tokens without caring other factor
     * The funds will be sent to treasury, and the team need to manually refund back to users affected
     *
     * @dev TODO: Needs to be for emergency.
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = _balance();
        nativeToken.safeTransfer(treasury, balance);
        
        emit EmergencyWithdraw(msg.sender, balance);
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of tokens to withdraw
     * @dev This function is only callable by admin.
     */
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(nativeToken), "Cannot be native token");
        require(_tokenAddress != address(gamePointToken), "Cannot be point token");
        IBEP20(_tokenAddress).safeTransfer(treasury, _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    /**
     * @notice Sets Reserved Amount of native token
     * Can be zero only if the owner want to leave the slot
     *
     * @dev Only callable by the contract admin.
     */
    function setAdmin(address _admin) external {
        require(_admin != address(0), "Address cannot be 0");
        require(msg.sender == ownerAccount, "Only the game owener can update admin");
        admin = _admin;

        emit AdminUpdated(msg.sender, _admin);
    }

    /**
     * @notice Sets Reserved Amount of native token
     * Can be zero only if the owner want to leave the slot
     *
     * @dev Only callable by the contract admin.
     */
    function setReservedAmount(uint256 _reservedAmount) external onlyOwner {
        reservedAmount = _reservedAmount;
        emit SetReservedAmount(reservedAmount);
    }

    /**
     * @notice Only if unlockLimit is set and the balance is less than unlockLimit
     * Then it's able to unlock
     */
    function setUnlockLimitAmount(uint256 _unlockLimit) external onlyOwner {
        unlockLimit = _unlockLimit;
        emit SetUnlockLimitAmount(_unlockLimit);
    }

    /**
     * @notice Sets performance fee
     * @dev Only callable by the contract admin.
     */
    function setPerformanceFee(uint256 _performanceFee) external onlyOwner {
        require(_performanceFee <= MAX_PERFORMANCE_FEE, "performanceFee cannot be more than MAX_PERFORMANCE_FEE");
        performanceFee = _performanceFee;
        emit SetPerformanceFee(performanceFee);
    }

    /**
     * @notice Sets treasury address
     * @dev Only callable by the contract owner.
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Cannot be zero address");
        treasury = _treasury;
        emit SetTreasury(treasury);
    }

    /**
     * @notice Sets treasury address
     * @dev Only callable by the contract owner.
     */
    function flipSuspendState() external onlyOwner {
        suspended = !suspended;

        emit StatusChanged(msg.sender, suspended);
    }

    /** View functions */
    function initialized() external view returns (bool) {
        return isInitialized;
    }

    function isSuspended() external view returns (bool) {
        return suspended;
    }

    function balanceOfPoints() external view returns (uint256) {
        return _balanceOfPoints();
    }

    function _balanceOfPoints() private view returns (uint256) {
        return gamePointToken.balanceOf(address(this));
    }

    function balance() external view returns (uint256) {
        return _balance();
    }

    function _balance() private view returns (uint256) {
        return nativeToken.balanceOf(address(this));
    }
}
