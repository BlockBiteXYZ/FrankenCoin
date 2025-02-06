pragma solidity ^0.8.0;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IFrankencoin} from "../stablecoin/IFrankencoin.sol";

contract BridgeHandler is CCIPReceiver {
    IFrankencoin public immutable ZCHF;

    error NotEnoughZCHF(uint256 required, uint256 available);
    error NotEnoughETH(uint256 required, uint256 available);

    event MessageSent(bytes32 messageId, uint256 zchfAmount, uint256 feesPaid);

    constructor(address router, IFrankencoin zchf) CCIPReceiver(router) {
        ZCHF = zchf;
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        // TODO: implement
    }

    function send(
        uint64 destinationChainSelector,
        address recipient,
        uint256 amount
    ) external payable returns (bytes32 messageId) {
        uint256 zchfBalance = ZCHF.balanceOf(address(this));
        if (zchfBalance < amount) {
            revert NotEnoughZCHF(amount, zchfBalance);
        }
        ZCHF.approve(i_ccipRouter, amount);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: ZCHF, amount: amount});
        Client.EVM2AnyMessage memory message = _getCCIPMessage(recipient, tokenAmounts, "", 20000);

        uint256 ethBalance = balanceOf(address(this));
        uint256 fees = router.getFee(destinationChainSelector, message);
        if (ethBalance < fees) {
            revert NotEnoughETH(fees, ethBalance);
        }

        messageId = IRouterClient(i_ccipRouter).ccipSend{value: fees}(destinationChainSelector, message);

        // return left overs
        payable(msg.sender).call{value: ethBalance - fees}("");

        emit MessageSent({messageId: messageId, zchfAmount: amount, feesPaid: fees});
    }

    function _getCCIPMessage(
        address receiver,
        Client.EVMTokenAmount[] memory tokenAmounts,
        bytes memory data,
        uint256 gasLimit
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(receiver),
                data: abi.encode(data),
                tokenAmounts: tokenAmounts,
                feeToken: address(0),
                extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: gasLimit}))
            });
    }
}
