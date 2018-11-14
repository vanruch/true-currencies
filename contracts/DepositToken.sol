pragma solidity ^0.4.23;

import "./CompliantToken.sol";

contract DepositToken is CompliantToken {
    
    string public constant IS_DEPOSIT_ADDRESS = "isDepositAddress"; 

    function transferAllArgs(address _from, address _to, uint256 _value) internal {
        uint value;
        bytes32 notes;
        address admin;
        uint time;
        (value, notes, admin, time) = registry.getAttribute(maskedAddress(_to), IS_DEPOSIT_ADDRESS);
        if (value != 0) {
            super.transferAllArgs(_from, address(value), _value);
        }
    }

    function maskedAddress(address addr) public constant returns (address) {
        bytes20 bytes20Address = cut(bytes32(uint256(addr) << 96));
        return address(bytes20Address);
    }

    function cut(bytes32 shiftedAddress) internal constant returns (bytes16 shortAddress) {
        assembly {
            let freemem_pointer := mload(0x40)
            mstore(freemem_pointer, shiftedAddress)
            shortAddress := mload(freemem_pointer)
        }
    }
}
