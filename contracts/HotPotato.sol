// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { 
    IAlluoToken 
} from "alluo-protocole/contracts/interfaces/IAlluoToken.sol";

import { 
    ISuperfluid,
    ISuperfluidToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import { 
    IConstantFlowAgreementV1 
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

import {
    CFAv1Library
} from "@superfluid-finance/ethereum-contracts/contracts/apps/CFAv1Library.sol";

import 'lib/protocol/packages/core/contracts/oracle/interfaces/OptimisticOracleV2Interface.sol';

contract Vault {
    
}

contract HotPotato {
    // **** GAME LOGIC GLOBAL VARS ****

    // 0: Game has not been initialized
    // 1: Game is in lobby, users are joining
    // 2: Game is active
    uint8 gameState;
    address HARD_RECIPIENT = 0xE091504578626BB2A83416A20E986b23FfEa95cb;
    address stibAlluoAddress = 0x2efC02E2cDCC1EF699f4aF7E98b20f8A2a30923d;
    
    address[] players;
    uint256 holder;

    uint256 MAX_PLAYERS = 5;

    // **** UMA PROTOCOL GLOBAL VARS ****

    // Create an Optimistic oracle instance at the deployed address on Polygon Mumbai.
    OptimisticOracleV2Interface oo = OptimisticOracleV2Interface(0x60E6140330F8FE31e785190F39C1B5e5e833c2a9); //CHANGE TO MAINNET VERSION LATER

    address target;
    bytes targetString;

    // Use the yes no idetifier
    bytes32 identifier = bytes32("YES_OR_NO_QUERY");
    bytes ancillaryData;
    uint256 requestTime = 0; // Store the request time so we can re-use it later.


    // **** ALLUO STREAMING LOGIC GLOBAL VALS ****

    Vault fundsVault;
    using CFAv1Library for CFAv1Library.InitData;
    
    //initialize cfaV1 variable
    CFAv1Library.InitData public cfaLib;
    ISuperfluidToken public alluoToken = ISuperfluidToken(0xEB796bdb90fFA0f28255275e16936D25d3418603);

    constructor(
        ISuperfluid host
    ) {
    
        //initialize InitData struct, and set equal to cfaV1
        cfaLib = CFAv1Library.InitData(
        host,
            //here, we are deriving the address of the CFA using the host contract
            IConstantFlowAgreementV1(
                address(0x49e565Ed1bdc17F3d220f72DF0857C26FA83F873)
            )

            //host.getAgreementClass(
                //     keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1")
                // )
        );
        
        fundsVault = new Vault();
    }

    function readGameState() public view returns (uint8) {
        return gameState;
    }

    function setGameState(uint8 _gameState) public {
        gameState = _gameState;
        
        if (gameState == 1) {
            initializeGame();
        }
    }

    function joinGame() public {
        require(players.length < MAX_PLAYERS);

        // TRANSFER ALLUO tokens
        players.push(msg.sender);

    }

    function initializeGame() internal {
        holder = uint(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))) % players.length;

        startStream(address(this));
    }

    function streamtest() public {

    }

    // Submit a data request to the Optimistic oracle.
    //potato holder requests yes or no query "give hot potato to [target] player" then proposes yes
    function tossPotatoInitiate(address _target, bytes memory _targetString) public {
        //[require there is no ongoing toss]?
        require(msg.sender == players[holder], "Cannot toss potato without being holder");

        // Post the question in ancillary data
        ancillaryData = bytes.concat("Q:Give hot potato to ", _targetString , " ? A:1 for yes. 0 for no.");

        target = _target;
        targetString = _targetString;

        requestTime = block.timestamp; // Set the request time to the current block time.
        IERC20 bondCurrency = IERC20(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6); // Use Görli WETH as the bond currency.
        uint256 reward = 0; // Set the reward to 0 (so we dont have to fund it from this contract).

        // Now, make the price request to the Optimistic oracle and set the liveness to 120 so it will settle in 2 minutes.
        //update so that liveness for each new request is equal to the dispute time of the last one? so game speeds up over time
        oo.requestPrice(identifier, requestTime, ancillaryData, bondCurrency, reward);
        oo.setCustomLiveness(identifier, requestTime, ancillaryData, 120);
    }

    function tossPotato() public {
        require(msg.sender == players[holder], "Cannot toss potato without being holder");

        //now propose yes
        oo.proposePriceFor(msg.sender,address(this), identifier, requestTime, ancillaryData, 1000000000000000000); //1e18 = yes
    }

    function disputeToss() public {
        //require that caller is target player
        require(msg.sender == target, "Only the target player can dispute");

        oo.disputePriceFor(msg.sender, address(this), identifier, requestTime, ancillaryData);
    }

    // Settle the request once it's gone through the liveness period of 30 seconds. This acts the finalize the voted on price.
    // In a real world use of the Optimistic Oracle this should be longer to give time to disputers to catch bat price proposals.
    function settleRequest() public {
        //will revert if the time period has not passed
        //or if it was successfully disputed
        oo.settle(address(this), identifier, requestTime, ancillaryData);

        //[include logic here to send the target the hot potato] (in other words send the superfluid stream)
        //set new holder equal to target
        uint256 target_id;

        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == target) {
                holder = i;
                target_id = i;
            }
        }
        transferPotato(target_id);
    }

    // Fetch the resolved price from the Optimistic Oracle that was settled.
    function getSettledData() public view returns (int256) {
        return oo.getRequest(address(this), identifier, requestTime, ancillaryData).resolvedPrice;
    }

    function transferPotato(uint256 newHolder) public {
        transferStream(newHolder);
    }

    // *** SUPERFLUID LOGIC ***


    function startStream(address recipient) public {
        // initialize superfluid stream, send to hardcode
        // bytes memory context = cfaLib.authorizeFlowOperatorWithFullControl(address(this), alluoToken);
        cfaLib.createFlow(address(fundsVault), alluoToken, 1);
    }

    function transferStream(uint256 newHolder) public {
        cfaLib.deleteFlowByOperator(players[holder], players[newHolder], alluoToken);
        
        // Split funds sent to the vault 
        for (uint256 i = 0; i < players.length; i++) {
            // Don't send funds to the holder (obviously)
            if (i != holder) {
                payable(players[i]).transfer(address(fundsVault).balance / (players.length -1));
            }
        }

        cfaLib.createFlow(address(fundsVault), alluoToken, 1);

    }

}
