pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "../contracts/modules/ArgentModule.sol";

/**
 * @notice Extends the ArgentModule to get the creation code of uniswap pairs locally
 * and enbale ERC20 refunds in tests.
 */
contract ArgentModuleTest is ArgentModule {

    bytes32 internal creationCode;

    constructor (
        IModuleRegistry _registry,
        IGuardianStorage _guardianStorage,
        ITransferStorage _userWhitelist,
        IAuthoriser _authoriser,
        address _uniswapRouter,
        uint256 _securityPeriod,
        uint256 _securityWindow,
        uint256 _recoveryPeriod,
        uint256 _lockPeriod
    )
        public
        ArgentModule(
            _registry,
            _guardianStorage,
            _userWhitelist,
            _authoriser,
            _uniswapRouter,
            _securityPeriod,
            _securityWindow,
            _recoveryPeriod,
            _lockPeriod)
    {
        address uniswapV2Factory = IUniswapV2Router01(_uniswapRouter).factory();
        (bool success, bytes memory _res) = uniswapV2Factory.staticcall(abi.encodeWithSignature("getKeccakOfPairCreationCode()"));
        if (success) {
            creationCode = abi.decode(_res, (bytes32));
        }
    }
    function getPairForSorted(address tokenA, address tokenB) internal override view returns (address pair) {
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                uniswapV2Factory,
                keccak256(abi.encodePacked(tokenA, tokenB)),
                creationCode
            ))));
    }
}