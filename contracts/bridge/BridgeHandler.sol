pragma solidity ^0.8.0;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IFrankencoin} from "../stablecoin/IFrankencoin.sol";
import {Equity} from "../equity/Equity.sol";

contract BridgeHandler is CCIPReceiver {
    IFrankencoin public immutable ZCHF;
    Equity public immutable FPS;

    error NotEnoughZCHF(uint256 required, uint256 available);
    error NotEnoughETH(uint256 required, uint256 available);

    event MessageSent(bytes32 messageId, uint256 zchfAmount, uint256 recipient, uint256 feesPaid);

    struct FPSSyncMessage {
        address holder;
        uint256 votes;
        uint256 delegatedVotes;
        uint256 totalVotes;
    }

    struct TokenTransferMessage {
        address recipient;
        // Add other information such as interestrate from savings module
    }

    constructor(address router, IFrankencoin zchf, Equity fps) CCIPReceiver(router) {
        ZCHF = zchf;
        FPS = fps;
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        // TODO: implement
    }

    /**
        @notice Transfers ZCHF and other information to destination chain
        @param destinationChainSelector CCIP selector of the destination chain
        @param receiver CCIP message receiver
        @param recipient ZCHF transfer recipient
        @param amount ZCHF amount to transfer
     */
    function sendZCHF(
        uint64 destinationChainSelector,
        address receiver,
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
        TokenTransferMessage memory message = TokenTransferMessage({recipient: recipient});
        Client.EVM2AnyMessage memory ccipMessage = _getCCIPMessage(receiver, tokenAmounts, abi.encode(message), 20000);

        (messageId, fees) = _sendCCIPMessage(ccipMessage, destinationChainSelector);
        emit MessageSent({messageId: messageId, zchfAmount: amount, recipient: recipient, feesPaid: fees});
    }


    /**
        @notice Informs destination chain about FPS voting rights
        @param destinationChainSelector CCIP selector of the destination chain
        @param receiver CCIP message receiver
        @param holder FPS Holder
        @param delegates[] Delegates who delegated to the holder
     */
    function syncFPS(
        uint64 destinationChainSelector,
        address receiver,
        address holder,
        address[] delegates
    ) external payable returns (bytes32 messageId) {
        uint256 holderVotes = FPS.votes(holder);
        uint256 delegatedVotes = FPS.votesDelegated(holder, delegates) - holderVotes;
        uint256 totalVotes = FPS.totalVotes();

        FPSSyncMessage memory message = FPSSyncMessage({
            holder: holder,
            votes: holderVotes,
            delegatedVotes: delegatedVotes,
            totalVotes: totalVotes
        });

        Client.EVM2AnyMessage memory ccipMessage = _getCCIPMessage(receiver, [], abi.encode(message), 20000);
        (messageId, fees) = _sendCCIPMessage(ccipMessage, destinationChainSelector);
        emit MessageSent({messageId: messageId, zchfAmount: 0, recipient: address(0), feesPaid: fees});
    }

    function _sendCCIPMessage(
        Client.EVM2AnyMessage memory message,
        uint64 destinationChainSelector
    ) internal returns (bytes32 messageId, uint256 fees) {
        uint256 ethBalance = balanceOf(address(this));
        fees = router.getFee(destinationChainSelector, message);
        if (ethBalance < fees) {
            revert NotEnoughETH(fees, ethBalance);
        }

        messageId = IRouterClient(i_ccipRouter).ccipSend{value: fees}(destinationChainSelector, message);

        // return left overs
        payable(msg.sender).call{value: ethBalance - fees}("");
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
