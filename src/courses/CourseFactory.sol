// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CourseNFT} from "./CourseNFT.sol";

/// @title CourseFactory
/// @notice Factory contract to deploy and track CourseNFT contracts.
contract CourseFactory is Ownable {
    address[] public courses;
    mapping(address => address[]) public coursesByCreator;
    mapping(address => bool)      public isDeployedCourse;
    address public defaultTreasury;

    event CourseCreated(
        address indexed courseAddress,
        address indexed creator,
        string  name,
        string  symbol,
        uint256 mintPrice,
        uint256 maxSupply
    );
    event DefaultTreasuryUpdated(address indexed newTreasury);

    error ZeroAddress();
    error IndexOutOfBounds(uint256 index, uint256 length);

    constructor(address _defaultTreasury) Ownable(msg.sender) {
        if (_defaultTreasury == address(0)) revert ZeroAddress();
        defaultTreasury = _defaultTreasury;
    }

    function createCourse(
        string  memory name,
        string  memory symbol,
        uint256        mintPrice,
        uint256        maxSupply,
        string  memory baseURI,
        string  memory privateContentURI,
        address        treasury,
        uint96         royaltyFeeBps
    ) external returns (address) {
        address courseTreasury = treasury == address(0) ? defaultTreasury : treasury;

        CourseNFT course = new CourseNFT(
            name, symbol, mintPrice, maxSupply,
            baseURI, privateContentURI, courseTreasury, royaltyFeeBps
        );
        course.transferOwnership(msg.sender);

        address courseAddress = address(course);
        courses.push(courseAddress);
        coursesByCreator[msg.sender].push(courseAddress);
        isDeployedCourse[courseAddress] = true;

        emit CourseCreated(courseAddress, msg.sender, name, symbol, mintPrice, maxSupply);
        return courseAddress;
    }

    function getAllCourses() external view returns (address[] memory) { return courses; }

    function getCoursesByCreator(address creator) external view returns (address[] memory) {
        return coursesByCreator[creator];
    }

    function getCourseCount() external view returns (uint256) { return courses.length; }

    function getCourseAtIndex(uint256 index) external view returns (address) {
        if (index >= courses.length) revert IndexOutOfBounds(index, courses.length);
        return courses[index];
    }

    function setDefaultTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        defaultTreasury = newTreasury;
        emit DefaultTreasuryUpdated(newTreasury);
    }
}
