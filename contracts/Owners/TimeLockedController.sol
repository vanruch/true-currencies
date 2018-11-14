pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./HasOwner.sol";
import "../TrueUSD.sol";
import "../../registry/contracts/Registry.sol";
import "../Proxy/OwnedUpgradeabilityProxy.sol";

/* This contract allows us to split ownership of the TrueUSD contract (and TrueUSD's Registry)
into two addresses. One, called the "owner" address, has unfettered control of the TrueUSD contract -
it can mint new tokens, transfer ownership of the contract, etc. However to make
extra sure that TrueUSD is never compromised, this owner key will not be used in
day-to-day operations, allowing it to be stored at a heightened level of security.
Instead, the owner appoints an various "admin" address. 
There are 3 different types of admin addresses;  MintKey, MintApprover, and MintChecker. 
MintKey can request and revoke and finalize mints one at a time.
MintChecker can pause individual mints or pause all mints.
MintApprover needs to approve the mint for any mint to be finalized.
Additionally, the MintKey can  only mint new tokens by calling a pair of functions - 
`requestMint` and `finalizeMint` - with significant gaps in time between the two calls.
This allows us to watch the blockchain and if we discover the mintkey has been
compromised and there are unauthorized operations underway, we can use the owner key
to pause the mint.

Rules to when a mint can be finalized:
 A requested mint can be finalized if and only if there exists a checktime P with the following properties:
  1. The mint was requested at least 30 min before P
  2. The current time is at least  2 hrs after P

*/

contract TimeLockedController {
    using SafeMath for uint256;

    struct MintOperation {
        address to;
        uint256 value;
        uint256 requestedBlock;
        uint256 numberOfApproval;
        bool paused;
        mapping(address => bool) approved; 
    }

    mapping(bytes32 => bool) public holidays; //hash of dates to boolean

    address public owner;
    address public pendingOwner;

    bool public initialized;

    uint256 public instantMintThreshold;
    uint256 public ratifiedMintThreshold;
    uint256 public jumboMintThreshold;


    uint256 public instantMintLimit; 
    uint256 public ratifiedMintLimit; 
    uint256 public jumboMintLimit;

    uint256 public instantMintPool; 
    uint256 public ratifiedMintPool; 
    uint256 public jumboMintPool;
    uint8 public ratifiedPoolRefillApprovals;

    uint8 constant public RATIFY_MINT_SIGS = 1;
    uint8 constant public JUMBO_MINT_SIGS = 3;

    bool public mintPaused;
    uint256 public mintReqInValidBeforeThisBlock; //all mint request before this block are invalid
    address public mintKey;
    MintOperation[] public mintOperations; //list of a mint requests
    
    TrueUSD public trueUSD;
    Registry public registry;
    address public trueUsdFastPause;

    string constant public IS_MINT_CHECKER = "isTUSDMintChecker";
    string constant public IS_MINT_RATIFIER = "isTUSDMintRatifier";

    modifier onlyFastPauseOrOwner() {
        require(msg.sender == trueUsdFastPause || msg.sender == owner, "must be pauser or owner");
        _;
    }

    modifier onlyMintKeyOrOwner() {
        require(msg.sender == mintKey || msg.sender == owner, "must be mintKey or owner");
        _;
    }

    modifier onlyMintCheckerOrOwner() {
        require(registry.hasAttribute(msg.sender, IS_MINT_CHECKER) || msg.sender == owner, "must be validator or owner");
        _;
    }

    modifier onlyMintRatifierOrOwner() {
        require(registry.hasAttribute(msg.sender, IS_MINT_RATIFIER) || msg.sender == owner, "must be ratifier or owner");
        _;
    }

    //mint operations by the mintkey cannot be processed on when mints are paused
    modifier mintNotPaused() {
        if (msg.sender != owner) {
            require(!mintPaused, "minting is paused");
        }
        _;
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event newOwnerPending(address indexed currentOwner, address indexed pendingOwner);
    event SetRegistry(address indexed registry);
    event TransferChild(address indexed child, address indexed newOwner);
    event RequestReclaimContract(address indexed other);
    event SetTrueUSD(TrueUSD newContract);
    event TrueUsdInitialized();
    
    event RequestMint(address indexed to, uint256 indexed value, uint256 indexed opIndex, address mintKey);
    event FinalizeMint(address indexed to, uint256 indexed value, uint256 indexed opIndex, address mintKey);
    event InstantMint(address indexed to, uint256 indexed value, address indexed mintKey);
    
    event TransferMintKey(address indexed previousMintKey, address indexed newMintKey);
    event MintRatified(uint256 indexed opIndex, address indexed ratifier);
    event RevokeMint(uint256 opIndex);
    event AllMintsPaused(bool status);
    event MintPaused(uint opIndex, bool status);
    event MintApproved(address approver, uint opIndex);
    event TrueUsdFastPauseSet(address _newFastPause);

    event MintThresholdChanged(uint instant, uint ratified, uint jumbo);
    event MintLimitsChanged(uint instant, uint ratified, uint jumbo);
    event InstantPoolRefilled();
    event RadifyPoolRefilled();
    event JumboPoolRefilled();


    /*
    ========================================
    Ownership functions
    ========================================
    */

    function initialize() external {
        require(!initialized, "already initialized");
        owner = msg.sender;
        initialized = true;
    }

    /**
    * @dev Throws if called by any account other than the owner.
    */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /**
    * @dev Modifier throws if called by any account other than the pendingOwner.
    */
    modifier onlyPendingOwner() {
        require(msg.sender == pendingOwner);
        _;
    }

    /**
    * @dev Allows the current owner to set the pendingOwner address.
    * @param newOwner The address to transfer ownership to.
    */
    function transferOwnership(address newOwner) external onlyOwner {
        pendingOwner = newOwner;
        emit newOwnerPending(owner , pendingOwner);
    }

    /**
    * @dev Allows the pendingOwner address to finalize the transfer.
    */
    function claimOwnership() external onlyPendingOwner {
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }
    
    /*
    ========================================
    proxy functions
    ========================================
    */

    function transferTusdProxyOwnership(address _newOwner) external onlyOwner {
        OwnedUpgradeabilityProxy(trueUSD).transferProxyOwnership(_newOwner);
    }

    function claimTusdProxyOwnership() external onlyOwner {
        OwnedUpgradeabilityProxy(trueUSD).claimProxyOwnership();
    }

    function upgradeTusdProxyImplTo(address _implementation) external onlyOwner {
        OwnedUpgradeabilityProxy(trueUSD).upgradeTo(_implementation);
    }

    /*
    ========================================
    Minting functions
    ========================================
    */

    /**
     * @dev define the threshold for a mint to be considered a small mint.
     small mints requires a smaller number of approvals
     */
    function setMintThresholds(uint256 _instant, uint256 _ratified, uint256 _jumbo) external onlyOwner {
        instantMintThreshold= _instant;
        ratifiedMintThreshold = _ratified;
        jumboMintThreshold = _jumbo;
        emit MintThresholdChanged(_instant, _ratified, _jumbo);
    }

    function setMintLimits(uint256 _instant, uint256 _ratified, uint256 _jumbo) external onlyOwner {
        instantMintLimit = _instant;
        ratifiedMintLimit = _ratified;
        jumboMintLimit = _jumbo;
        emit MintLimitsChanged(_instant, _ratified, _jumbo);
    }


    function refillInstantMintPool() external onlyMintRatifierOrOwner {
        ratifiedMintPool = ratifiedMintPool.sub(instantMintLimit.sub(instantMintPool));
        instantMintPool = instantMintLimit;
        emit InstantPoolRefilled();
    }

    function refillRatifiedMintPool() external onlyMintRatifierOrOwner {
        if (msg.sender != owner) {
            if (ratifiedPoolRefillApprovals < 2) {
                ratifiedPoolRefillApprovals += 1;
                return;
            } 
        }
        jumboMintPool = jumboMintPool.sub(ratifiedMintLimit.sub(ratifiedMintPool));
        ratifiedMintPool = ratifiedMintLimit;
        ratifiedPoolRefillApprovals = 0;
        emit RadifyPoolRefilled();
    }

    function refillJumboMintPool() external onlyOwner {
        jumboMintPool = jumboMintLimit;
        emit JumboPoolRefilled();
    }

    /**
     * @dev mintKey initiates a request to mint _value TrueUSD for account _to
     * @param _to the address to mint to
     * @param _value the amount requested
     */
    function requestMint(address _to, uint256 _value) external mintNotPaused onlyMintKeyOrOwner {
        MintOperation memory op = MintOperation(_to, _value, block.number, 0, false);
        mintOperations.push(op);
        emit RequestMint(_to, _value, mintOperations.length, msg.sender);
    }

    function instantMint(address _to, uint256 _value) mintNotPaused onlyMintKeyOrOwner {
        require(_value <= instantMintPool && _value <= instantMintThreshold);
        instantMintPool = instantMintPool.sub(_value);
        emit InstantMint(_to, _value, msg.sender);
        trueUSD.mint(_to, _value);
    }

    function ratifyMint(uint256 _index, address _to, uint256 _value) external mintNotPaused onlyMintRatifierOrOwner {
        MintOperation memory op = mintOperations[_index];
        require(op.to == _to);
        require(op.value == _value);
        require(!mintOperations[_index].approved[msg.sender], "already approved");
        mintOperations[_index].approved[msg.sender] = true;
        mintOperations[_index].numberOfApproval = mintOperations[_index].numberOfApproval.add(1);
        emit MintRatified(_index, msg.sender);
        if (hasEnoughApproval(mintOperations[_index].numberOfApproval, _value)){
            finalizeMint(_index);
        }
    }

    /**
     * @dev finalize a mint request, mint the amount requested to the specified address
     @param _index of the request (visible in the RequestMint event accompanying the original request)
     */
    function finalizeMint(uint256 _index) public {
        MintOperation memory op = mintOperations[_index];
        address to = op.to;
        uint256 value = op.value;
        if (msg.sender != owner) {
            require(canFinalize(_index));
            _subtractFromMintPool(value);
        }
        delete mintOperations[_index];
        trueUSD.mint(to, value);
        emit FinalizeMint(to, value, _index, msg.sender);
    }

    function _subtractFromMintPool(uint256 _value) internal {
        if (_value <= ratifiedMintPool && _value <= ratifiedMintThreshold) {
            ratifiedMintPool = ratifiedMintPool.sub(_value);
        } else {
            jumboMintPool = jumboMintPool.sub(_value);
        }
    }

    /**
     * @dev compute if the number of approvals is enough for a given mint amount
     */
    function hasEnoughApproval(uint256 _numberOfApproval, uint256 _value) public view returns (bool) {
        if (msg.sender == owner) {
            return true;
        }
        if (_value <= ratifiedMintPool && _value <= ratifiedMintThreshold) {
            if (_numberOfApproval >= RATIFY_MINT_SIGS){
                return true;
            }
        }
        if (_value <= jumboMintPool && _value <= jumboMintThreshold) {
            if (_numberOfApproval >= JUMBO_MINT_SIGS){
                return true;
            }
        }
        return false;
    }

    /**
     * @dev compute if a mint request meets all the requirements to be finalized
     utility function for a front end
     */
    function canFinalize(uint256 _index) public view returns(bool) {
        MintOperation memory op = mintOperations[_index];
        require(op.requestedBlock > mintReqInValidBeforeThisBlock, "this mint is invalid"); //also checks if request still exists
        require(!op.paused, "this mint is paused");
        require(hasEnoughApproval(op.numberOfApproval, op.value), "not enough approvals");
        return true;
    }

    /** 
    *@dev revoke a mint request, Delete the mintOperation
    *@param index of the request (visible in the RequestMint event accompanying the original request)
    */
    function revokeMint(uint256 _index) external onlyMintKeyOrOwner {
        delete mintOperations[_index];
        emit RevokeMint(_index);
    }

    function mintOperationCount() public view returns (uint256) {
        return mintOperations.length;
    }

    /*
    ========================================
    Key management
    ========================================
    */

    /** 
    *@dev Replace the current mintkey with new mintkey 
    *@param _newMintKey address of the new mintKey
    */
    function transferMintKey(address _newMintKey) external onlyOwner {
        require(_newMintKey != address(0), "new mint key cannot be 0x0");
        emit TransferMintKey(mintKey, _newMintKey);
        mintKey = _newMintKey;
    }
 
    /*
    ========================================
    Mint Pausing
    ========================================
    */

    /** 
    *@dev invalidates all mint request initiated before the current block 
    */
    function invalidateAllPendingMints() external onlyOwner {
        mintReqInValidBeforeThisBlock = block.number;
    }

    /** 
    *@dev pause any further mint request and mint finalizations 
    */
    function pauseMints() external onlyMintCheckerOrOwner {
        mintPaused = true;
        emit AllMintsPaused(true);
    }

    /** 
    *@dev unpause any further mint request and mint finalizations 
    */
    function unPauseMints() external onlyOwner {
        mintPaused = false;
        emit AllMintsPaused(false);
    }

    /** 
    *@dev pause a specific mint request
    *@param  _opIndex the index of the mint request the caller wants to pause
    */
    function pauseMint(uint _opIndex) external onlyMintCheckerOrOwner {
        mintOperations[_opIndex].paused = true;
        emit MintPaused(_opIndex, true);
    }

    /** 
    *@dev unpause a specific mint request
    *@param  _opIndex the index of the mint request the caller wants to unpause
    */
    function unpauseMint(uint _opIndex) external onlyOwner {
        mintOperations[_opIndex].paused = false;
        emit MintPaused(_opIndex, false);
    }

    /*
    ========================================
    set and claim contracts, administrative
    ========================================
    */

    // function incrementBurnAddressCount() external onlyOwner {
    //     trueUSD.;
    //     emit SetTrueUSD(_newContract);
    // }

    /** 
    *@dev Update this contract's trueUSD pointer to newContract (e.g. if the
    contract is upgraded)
    */
    function setTrueUSD(TrueUSD _newContract) external onlyOwner {
        trueUSD = _newContract;
        emit SetTrueUSD(_newContract);
    }

    function initializeTrueUSD(uint256 _totalSupply) external onlyOwner {
        trueUSD.initialize(_totalSupply);
        emit TrueUsdInitialized();
    }

    /** 
    *@dev Update this contract's registry pointer to _registry
    */
    function setRegistry(Registry _registry) external onlyOwner {
        registry = _registry;
        emit SetRegistry(registry);
    }

    /** 
    *@dev update TrueUSD's name and symbol
    */
    function changeTokenName(string _name, string _symbol) external onlyOwner {
        trueUSD.changeTokenName(_name, _symbol);
    }

    /** 
    *@dev Swap out TrueUSD's permissions registry
    *@param _registry new registry for trueUSD
    */
    function setTusdRegistry(Registry _registry) external onlyOwner {
        trueUSD.setRegistry(_registry);
    }

    /** 
    *@dev Claim ownership of an arbitrary HasOwner contract
    */
    function issueClaimOwnership(address _other) public onlyOwner {
        HasOwner other = HasOwner(_other);
        other.claimOwnership();
    }

    /** 
    *@dev calls setBalanceSheet(address) and setAllowanceSheet(address) on the _proxy contract
    @param _proxy the contract that inplments setBalanceSheet and setAllowanceSheet
    @param _balanceSheet HasOwner storage contract
    @param _alowanceSheet HasOwner storage contract
    */
    function claimStorageForProxy(
        address _proxy,
        HasOwner _balanceSheet,
        HasOwner _alowanceSheet) external onlyOwner {

        //call to claim the storage contract with the new delegate contract
        require(address(_proxy).call(bytes4(keccak256("setBalanceSheet(address)")), _balanceSheet));
        require(address(_proxy).call(bytes4(keccak256("setAllowanceSheet(address)")), _alowanceSheet));
    }

    /** 
    *@dev Transfer ownership of _child to _newOwner.
    Can be used e.g. to upgrade this TimeLockedController contract.
    *@param _child contract that timeLockController currently Owns 
    *@param _newOwner new owner/pending owner of _child
    */
    function transferChild(HasOwner _child, address _newOwner) external onlyOwner {
        _child.transferOwnership(_newOwner);
        emit TransferChild(_child, _newOwner);
    }

    /** 
    *@dev Transfer ownership of a contract from trueUSD to this TimeLockedController.
    Can be used e.g. to reclaim balance sheet
    in order to transfer it to an upgraded TrueUSD contract.
    *@param _other address of the contract to claim ownership of
    */
    function requestReclaimContract(HasOwner _other) public onlyOwner {
        trueUSD.reclaimContract(_other);
        emit RequestReclaimContract(_other);
    }

    /** 
    *@dev send all ether in trueUSD address to the owner of timeLockController 
    */
    function requestReclaimEther() external onlyOwner {
        trueUSD.reclaimEther(owner);
    }

    /** 
    *@dev transfer all tokens of a particular type in trueUSD address to the
    owner of timeLockController 
    *@param _token token address of the token to transfer
    */
    function requestReclaimToken(ERC20 _token) external onlyOwner {
        trueUSD.reclaimToken(_token, owner);
    }

    /** 
    *@dev set new contract to which tokens look to to see if it's on the supported fork
    *@param _newGlobalPause address of the new contract
    */
    function setGlobalPause(address _newGlobalPause) external onlyOwner {
        trueUSD.setGlobalPause(_newGlobalPause);
    }

    /** 
    *@dev set new contract to which specified address can send eth to to quickly pause trueUSD
    *@param _newFastPause address of the new contract
    */
    function setTrueUsdFastPause(address _newFastPause) external onlyOwner {
        trueUsdFastPause = _newFastPause;
        emit TrueUsdFastPauseSet(_newFastPause);
    }

    /** 
    *@dev pause all pausable actions on TrueUSD, mints/burn/transfer/approve
    */
    function pauseTrueUSD() external onlyFastPauseOrOwner {
        trueUSD.pause();
    }

    /** 
    *@dev unpause all pausable actions on TrueUSD, mints/burn/transfer/approve
    */
    function unpauseTrueUSD() external onlyOwner {
        trueUSD.unpause();
    }
    
    /** 
    *@dev wipe balance of a blacklisted address
    *@param _blacklistedAddress address whose balance will be wiped
    */
    function wipeBlackListedTrueUSD(address _blacklistedAddress) external onlyOwner {
        trueUSD.wipeBlacklistedAccount(_blacklistedAddress);
    }

    /** 
    *@dev Change the minimum and maximum amounts that TrueUSD users can
    burn to newMin and newMax
    *@param _min minimum amount user can burn at a time
    *@param _max maximum amount user can burn at a time
    */
    function setBurnBounds(uint256 _min, uint256 _max) external onlyOwner {
        trueUSD.setBurnBounds(_min, _max);
    }

    /** 
    *@dev Change the transaction fees charged on transfer/mint/burn
    */
    function changeStakingFees(
        uint256 _transferFeeNumerator,
        uint256 _transferFeeDenominator,
        uint256 _mintFeeNumerator,
        uint256 _mintFeeDenominator,
        uint256 _mintFeeFlat,
        uint256 _burnFeeNumerator,
        uint256 _burnFeeDenominator,
        uint256 _burnFeeFlat) external onlyOwner {
        trueUSD.changeStakingFees(
            _transferFeeNumerator,
            _transferFeeDenominator,
            _mintFeeNumerator,
            _mintFeeDenominator,
            _mintFeeFlat,
            _burnFeeNumerator,
            _burnFeeDenominator,
            _burnFeeFlat);
    }

    /** 
    *@dev Change the recipient of staking fees to newStaker
    *@param _newStaker new staker to send staking fess to
    */
    function changeStaker(address _newStaker) external onlyOwner {
        trueUSD.changeStaker(_newStaker);
    }

    /** 
    *@dev Owner can send ether balance in contract address
    *@param _to address to which the funds will be send to
    */
    function reclaimEther(address _to) external onlyOwner {
        _to.transfer(address(this).balance);
    }

    /** 
    *@dev Owner can send erc20 token balance in contract address
    *@param _token address of the token to send
    *@param _to address to which the funds will be send to
    */
    function reclaimToken(ERC20 _token, address _to) external onlyOwner {
        uint256 balance = _token.balanceOf(this);
        _token.transfer(_to, balance);
    }

    function() external {}
}