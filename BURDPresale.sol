// SPDX-License-Identifier: MIT
/**
 *
 *
 *    $BURD Presale Contract
 *
 *
 *
 **/

pragma solidity ^0.7.4;

import "./Context.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";

abstract contract DateTimeAPI {
    /*
     *  Abstract contract for interfacing with the DateTime contract.
     *
     */
    function isLeapYear(uint16 year) public pure virtual returns (bool);

    function toTimestamp(
        uint16 year,
        uint8 month,
        uint8 day
    ) public pure virtual returns (uint256 timestamp);

    function toTimestamp(
        uint16 year,
        uint8 month,
        uint8 day,
        uint8 hour,
        uint8 minute,
        uint8 second
    ) public pure virtual returns (uint256 timestamp);
}

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract BURDPresale is Ownable {
    using SafeMath for uint256;

    IERC20 public token;

    uint256 public privPresaleStartTime = 1634810400;
    uint256 public privPresaleEndTime = 1635372000;

    uint256 public pubPresaleStartTime = 1634810400;
    uint256 public pubPresaleEndTime = 1635372000;

    uint256 public privPresaleCap = 100_000_000e9; //10% of total supply
    uint256 public pubPresaleCap = 100_000_000e9; //10% of total supply

    uint256 public privPresalePrice = 8000; // $0.008 USD (decimal 6)
    uint256 public pubPresalePrice = 9000; // $0.009 USD

    uint256 public privPresaleMinLimit = 200_000e6;   //USD
    uint256 public pubPresaleMinLimit = 2_000e6;     //USD

    uint256 public privPresaleTokenMaxLimit = 100_000_000e9;   //BURD
    uint256 public pubPresaleTokenMaxLimit = 10_000_000e9;     //BURD

    bool public isClaimable = false;
    bool public endedPresale = false;
    bool public enableWhitelist = false;

    struct User {
        uint256 bnbAmount;
        uint256 burdAmount;
    }

    mapping(address => bool) privWhiteList;
    mapping(address => User) privUsers;
    mapping(uint256 => address) privUserIDs;
    uint256 public privUserCount = 0;
    uint256 public privSoldTokenAmount = 0;
    uint256 public privTotalPurchased = 0;

    mapping(address => bool) pubWhiteList;
    mapping(address => User) pubUsers;
    mapping(uint256 => address) pubUserIDs;
    uint256 public pubUserCount = 0;
    uint256 public pubSoldTokenAmount = 0;
    uint256 public pubTotalPurchased = 0;

    AggregatorV3Interface internal priceFeedBNB;

    address serviceWallet;

    constructor() {
        priceFeedBNB = AggregatorV3Interface(
            0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE //bsc mainnet
        );

        serviceWallet = owner();
    }

    function buyPrivBURD() external payable {
        require(endedPresale == false, "Ended Presale");
        require(checkPrivWhiteList(msg.sender), "Not white list user");

        uint256 bnbAmount = msg.value;
        uint256 bnbPrice = getBNBPrice();
        uint256 usdAmount = bnbAmount.mul(bnbPrice).div(1e20);
        require(usdAmount >= privPresaleMinLimit, "Less than minimun limit");

        uint256 burdAmount = usdAmount.mul(1e9).div(privPresalePrice);
        privSoldTokenAmount = privSoldTokenAmount.add(burdAmount);
        require(
            privSoldTokenAmount <= privPresaleCap,
            "Insufficient Token Balance"
        );

        uint256 withdrawAmount = burdAmount.mul(25).div(100); //send 25% immediately

        if (privUserExists(msg.sender)) {
            User storage user = privUsers[msg.sender];
            user.bnbAmount = user.bnbAmount.add(bnbAmount);

            uint256 newAmount = user.burdAmount.add(burdAmount.sub(withdrawAmount));
            require(newAmount <= privPresaleTokenMaxLimit, "Token max limit exceeded");

            user.burdAmount = newAmount;
        } else {
            uint256 newAmount = burdAmount.sub(withdrawAmount);
            require(newAmount <= privPresaleTokenMaxLimit, "Token max limit exceeded");

            privUsers[msg.sender] = User({
                bnbAmount: bnbAmount,
                burdAmount: newAmount
            });
            privUserIDs[privUserCount] = msg.sender;

            privUserCount++;
        }

        token.transfer(msg.sender, withdrawAmount);

        privTotalPurchased = privTotalPurchased.add(bnbAmount);
    }

    function buyPubBURD() external payable {
        require(endedPresale == false, "Ended Presale");
        require(checkPubWhiteList(msg.sender), "Not white list user");

        uint256 bnbAmount = msg.value;
        uint256 bnbPrice = getBNBPrice();
        uint256 usdAmount = bnbAmount.mul(bnbPrice).div(1e20);
        require(usdAmount >= pubPresaleMinLimit, "Less than minimun limit");

        uint256 burdAmount = usdAmount.mul(1e9).div(pubPresalePrice);
        pubSoldTokenAmount = pubSoldTokenAmount.add(burdAmount);
        require(
            pubSoldTokenAmount <= pubPresaleCap,
            "Insufficient Token Balance"
        );

        if (pubUserExists(msg.sender)) {
            User storage user = pubUsers[msg.sender];
            user.bnbAmount = user.bnbAmount.add(bnbAmount);
            
            uint256 newAmount = user.burdAmount.add(burdAmount);
            require(newAmount <= pubPresaleTokenMaxLimit, "Token max limit exceeded");

            user.burdAmount = newAmount;
        } else {
            require(burdAmount <= pubPresaleTokenMaxLimit, "Token max limit exceeded");

            pubUsers[msg.sender] = User({
                bnbAmount: bnbAmount,
                burdAmount: burdAmount
            });
            pubUserIDs[pubUserCount] = msg.sender;
            pubUserCount++;
        }

        pubTotalPurchased = pubTotalPurchased.add(bnbAmount);
    }

    function claimPubBURD() public {
        require(isClaimable, "Still not claimable");
        require(pubUserExists(msg.sender), "User does not exist");

        User storage user = pubUsers[msg.sender];
        uint256 tokenAmount = user.burdAmount;

        require(tokenAmount > 0, "withdrew already");

        user.burdAmount = 0;
        token.transfer(msg.sender, tokenAmount);
    }

    function privUserExists(address userAddress) public view returns (bool) {
        return (privUsers[userAddress].bnbAmount != 0);
    }

    function pubUserExists(address userAddress) public view returns (bool) {
        return (pubUsers[userAddress].bnbAmount != 0);
    }

    function privSaleUserInfo(uint256 index)
        public
        view
        returns (
            uint256 bnbAmount,
            uint256 burdAmount
        )
    {
        require(index < privUserCount, "Invalid index");

        return privSaleUserInfoFromAddress(privUserIDs[index]);
    }

    function privSaleUserInfoFromAddress(address userAddress)
        public
        view
        returns (
            uint256 bnbAmount,
            uint256 burdAmount
        )
    {
        require(privUserExists(userAddress), "Not exists");

        User memory user = privUsers[userAddress];

        bnbAmount = user.bnbAmount;
        burdAmount = user.burdAmount;
    }

    function pubSaleUserInfo(uint256 index)
        public
        view
        returns (
            uint256 bnbAmount,
            uint256 burdAmount
        )
    {
        require(index < pubUserCount, "Invalid index");

        return pubSaleUserInfoFromAddress(pubUserIDs[index]);
    }

    function pubSaleUserInfoFromAddress(address userAddress)
        public
        view
        returns (
            uint256 bnbAmount,
            uint256 burdAmount
        )
    {
        require(pubUserExists(userAddress), "Not exists");

        User memory user = pubUsers[userAddress];

        bnbAmount = user.bnbAmount;
        burdAmount = user.burdAmount;
    }

    function estimateAmount(uint256 bnbAmount, uint256 price)
        public
        view
        returns (uint256, uint256)
    {
        uint256 bnbPrice = getBNBPrice();
        uint256 usdAmount = bnbAmount.mul(bnbPrice).div(1e20);
        uint256 burdAmount = usdAmount.mul(1e9).div(price);

        return (usdAmount, burdAmount);
    }

    function getBNBPrice() public view returns (uint256) {
        (
            uint80 roundID,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = priceFeedBNB.latestRoundData();

        return uint256(price);
    }

    function checkPrivWhiteList(address userAddress)
        public
        view
        returns (bool)
    {
        if( enableWhitelist ) {
            if (privWhiteList[userAddress]) return true;
            return false;
        }

        return true;
    }

    function checkPubWhiteList(address userAddress) public view returns (bool) {
        if( enableWhitelist ) {
            if (pubWhiteList[userAddress]) return true;
            return false;
        }

        return true;
    }

    function tokenBalance() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    //////////////////////////////////////////////////////////
    function setToken(IERC20 _token) public onlyOwner {
        token = _token;
    }

    function setTime(
        uint16 year,
        uint8 month,
        uint8 day,
        uint8 hour,
        uint8 minute,
        uint8 second,
        uint8 flag
    ) public onlyOwner {
        uint256 timestamp = toTimestamp(year, month, day, hour, minute, second);

        if (flag == 0) privPresaleStartTime = timestamp;
        else if (flag == 1) privPresaleEndTime = timestamp;
        else if (flag == 2) pubPresaleStartTime = timestamp;
        else if (flag == 3) pubPresaleEndTime = timestamp;
    }

    function setPrivPresaleCap(uint256 cap) public onlyOwner {
        privPresaleCap = cap;
    }

    function setPubPresaleCap(uint256 cap) public onlyOwner {
        pubPresaleCap = cap;
    }

    function setPrivPresaleMinLimit(uint256 _privPresaleMinLimit)
        public
        onlyOwner
    {
        privPresaleMinLimit = _privPresaleMinLimit;
    }

    function setPubPresaleMinLimit(uint256 _pubPresaleMinLimit)
        public
        onlyOwner
    {
        pubPresaleMinLimit = _pubPresaleMinLimit;
    }

    function setPrivPresaleTokenMaxLimit(uint256 _privPresaleTokenMaxLimit)
        public
        onlyOwner
    {
        privPresaleTokenMaxLimit = _privPresaleTokenMaxLimit;
    }

    function setPubPresaleTokenMaxLimit(uint256 _pubPresaleTokenMaxLimit)
        public
        onlyOwner
    {
        pubPresaleTokenMaxLimit = _pubPresaleTokenMaxLimit;
    }

    function addPrivWhiteList(address userAddress) public onlyOwner {
        require(checkPrivWhiteList(userAddress) != true, "Already exists");
        privWhiteList[userAddress] = true;
    }

    function removePrivWhiteList(address userAddress) public onlyOwner {
        require(checkPrivWhiteList(userAddress) == true, "No exist.");
        require(privUserExists(userAddress) == false, "Already purchased");
        privWhiteList[userAddress] = false;
    }

    function addPubWhiteList(address userAddress) public onlyOwner {
        require(checkPubWhiteList(userAddress) != true, "Already exists");
        pubWhiteList[userAddress] = true;
    }

    function removePubWhiteList(address userAddress) public onlyOwner {
        require(checkPubWhiteList(userAddress) == true, "No exist.");
        require(pubUserExists(userAddress) == false, "Already purchased");
        pubWhiteList[userAddress] = false;
    }

    function setClaimable(bool claim) public onlyOwner {
        isClaimable = claim;
    }

    function setWhitelistEnable(bool enable) public onlyOwner {
        enableWhitelist = enable;
    }

    function endPresale() public onlyOwner {
        endedPresale = true;
    }

    function setServiceWallet(address _serviceWallet) public onlyOwner {
        serviceWallet = _serviceWallet;
    }

    function withdraw() public onlyOwner {
        address payable wallet = address(uint160(serviceWallet));
        uint256 amount = address(this).balance;
        wallet.transfer(amount);
    }

    function withdrawExtraToken(address extraTokenWallet, uint256 amount)
        public
        onlyOwner
    {
        if( amount == 0 )
            token.transfer(extraTokenWallet, tokenBalance());
        else 
            token.transfer(extraTokenWallet, amount);
    }

    /**
     * Utils
     */
    //////////////////////////////////////////////////////////////////

    function isLeapYear(uint16 year) private pure returns (bool) {
        if (year % 4 != 0) {
            return false;
        }
        if (year % 100 != 0) {
            return true;
        }
        if (year % 400 != 0) {
            return false;
        }
        return true;
    }

    function toTimestamp(
        uint16 year,
        uint8 month,
        uint8 day
    ) private pure returns (uint256 timestamp) {
        return toTimestamp(year, month, day, 0, 0, 0);
    }

    function toTimestamp(
        uint16 year,
        uint8 month,
        uint8 day,
        uint8 hour,
        uint8 minute,
        uint8 second
    ) private pure returns (uint256 timestamp) {
        uint32 DAY_IN_SECONDS = 86400;
        uint32 YEAR_IN_SECONDS = 31536000;
        uint32 LEAP_YEAR_IN_SECONDS = 31622400;

        uint32 HOUR_IN_SECONDS = 3600;
        uint32 MINUTE_IN_SECONDS = 60;

        uint16 ORIGIN_YEAR = 1970;

        uint16 i;

        // Year
        for (i = ORIGIN_YEAR; i < year; i++) {
            if (isLeapYear(i)) {
                timestamp += LEAP_YEAR_IN_SECONDS;
            } else {
                timestamp += YEAR_IN_SECONDS;
            }
        }

        // Month
        uint8[12] memory monthDayCounts;
        monthDayCounts[0] = 31;
        if (isLeapYear(year)) {
            monthDayCounts[1] = 29;
        } else {
            monthDayCounts[1] = 28;
        }
        monthDayCounts[2] = 31;
        monthDayCounts[3] = 30;
        monthDayCounts[4] = 31;
        monthDayCounts[5] = 30;
        monthDayCounts[6] = 31;
        monthDayCounts[7] = 31;
        monthDayCounts[8] = 30;
        monthDayCounts[9] = 31;
        monthDayCounts[10] = 30;
        monthDayCounts[11] = 31;

        for (i = 1; i < month; i++) {
            timestamp += DAY_IN_SECONDS * monthDayCounts[i - 1];
        }

        // Day
        timestamp += DAY_IN_SECONDS * (day - 1);

        // Hour
        timestamp += HOUR_IN_SECONDS * (hour);

        // Minute
        timestamp += MINUTE_IN_SECONDS * (minute);

        // Second
        timestamp += second;

        return timestamp;
    }
}
