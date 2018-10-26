pragma solidity ^0.4.23;

/*
Returns address with the last 10 bytes (20 characters) zeroed out
*/
contract AddressUtils {
    function shortenAddress(address addr) public pure returns (address){
        bytes20 bytes20Address = cut(bytes32(uint256(addr) << 96));
        return address(bytes20Address);
    }

    function cut(bytes32 shiftedAddress) internal pure returns (bytes10 halfOfAddress) {
        assembly {
            let freemem_pointer := mload(0x40)
            mstore(freemem_pointer, shiftedAddress)
            halfOfAddress := mload(freemem_pointer)
        }
    }
} 
