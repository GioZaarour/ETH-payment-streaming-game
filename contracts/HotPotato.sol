pragma solidity 0.8.9;
import "@uma/core/contracts/oracle/interfaces/OptimisticOracleV2Interface.sol";

contract HotPotato {
    // Create an Optimistic oracle instance at the deployed address on Görli.
    OptimisticOracleV2Interface oo = OptimisticOracleV2Interface(0xA5B9d8a0B0Fa04Ba71BDD68069661ED5C0848884); //CHANGE TO MAINNET VERSION LATER

    address holder;
    address target;
    bytes targetString;

    // Use the yes no idetifier
    bytes32 identifier = bytes32("YES_OR_NO_QUERY");
    bytes ancillaryData;
    uint256 requestTime = 0; // Store the request time so we can re-use it later.

    //this constructor is temporary (for testing)
    constructor(address _firstHolder) {
        holder = _firstHolder;
    }

    // Submit a data request to the Optimistic oracle.
    //potato holder requests yes or no query "give hot potato to [target] player" then proposes yes
    function tossPotato1(address _target, bytes memory _targetString) public {
        //[require there is no ongoing toss]?
        require(msg.sender == holder, "Cannot toss potato without being holder");

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

    function tossPotato2() public {
        require(msg.sender == holder, "Cannot toss potato without being holder");

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
        holder = target;
    }

    // Fetch the resolved price from the Optimistic Oracle that was settled.
    function getSettledData() public view returns (int256) {
        return oo.getRequest(address(this), identifier, requestTime, ancillaryData).resolvedPrice;
    }

}