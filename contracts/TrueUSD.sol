pragma solidity ^0.4.23;

import "./modularERC20/ModularPausableToken.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./BurnableTokenWithBounds.sol";
import "./CompliantToken.sol";
import "./TokenWithFees.sol";
import "./RedeemToken.sol";

// This is the top-level ERC20 contract, but most of the interesting functionality is
// inherited - see the documentation on the corresponding contracts.
contract TrueUSD is 
ModularPausableToken, 
BurnableTokenWithBounds, 
CompliantToken, 
TokenWithFees, 
RedeemToken
{
    using SafeMath for *;

    uint8 public constant DECIMALS = 18;
    uint8 public constant ROUNDING = 2;

    event ChangeTokenName(string newName, string newSymbol);

    /**  
    *@dev set the totalSupply of the contract for delegation purposes
    Can only be set once.
    */
    function initialize(uint256 _totalSupply) public {
        require(!initialized, "already initialized");
        initialized = true;
        owner = msg.sender;
        totalSupply_ = _totalSupply;
        burnMin = 10000 * 10**uint256(DECIMALS);
        burnMax = 20000000 * 10**uint256(DECIMALS);
        staker = msg.sender;
        name = "TrueUSD";
        symbol = "TUSD";
    }

    function changeTokenName(string _name, string _symbol) external onlyOwner {
        name = _name;
        symbol = _symbol;
        emit ChangeTokenName(_name, _symbol);
    }

    // Alternatives to the normal NoOwner functions in case this contract's owner
    // can't own ether or tokens.
    // Note that we *do* inherit reclaimContract from NoOwner: This contract
    // does have to own contracts, but it also has to be able to relinquish them.
    function reclaimEther(address _to) external onlyOwner {
        _to.transfer(address(this).balance);
    }

    function reclaimToken(ERC20 token, address _to) external onlyOwner {
        uint256 balance = token.balanceOf(this);
        token.transfer(_to, balance);
    }

    function reclaimContract(address contractAddr) external onlyOwner {
        Ownable contractInst = Ownable(contractAddr);
        contractInst.transferOwnership(owner);
    }

    function burnAllArgs(address _burner, uint256 _value, string _note) internal {
        //round down burn amount to cent
        uint burnAmount = _value.div(10 ** uint256(DECIMALS - ROUNDING)).mul(10 ** uint256(DECIMALS - ROUNDING));
        super.burnAllArgs(_burner, burnAmount, _note);
    }

    /**
    * @dev Disallows direct send by settings a default function without the `payable` flag.
    */
    function() external {}
}
