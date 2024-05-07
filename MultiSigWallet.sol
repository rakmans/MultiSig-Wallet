// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/interfaces/IERC1155.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract MultiSigWallet is ERC721Holder, ERC1155Holder {
    bool internal locked;

    event Deposit(address indexed sender, uint256 amount, uint256 balance);
    event SubmitTransaction(
        address indexed owner,
        uint256 indexed txIndex,
        address indexed to,
        uint256 value,
        address currencyAdrress,
        uint256 currencyType
    );
    event SubmitTransactionOwner(
        address indexed owner,
        uint256 indexed txIndex,
        address ownerSuggested,
        uint256 numConfirmations,
        bool addOwner
    );
    event ConfirmTransaction(address indexed owner, uint256 indexed txIndex);
    event RevokeConfirmation(address indexed owner, uint256 indexed txIndex);
    event ExecuteTransaction(address indexed owner, uint256 indexed txIndex);
    event AddOwner(address indexed newOwner);
    event RemoveOwner(address indexed Owner);

    mapping(address => bool) public isOwner;
    uint256 public numConfirmationsRequired;

    struct Transaction {
        address to;
        uint256 value;
        bool executed;
        uint256 numConfirmations;
        uint8 currencyType;
        address currencyAdrress;
        uint256 ID;
    }
    struct TransactionOwner {
        address owner;
        bool executed;
        uint256 numConfirmations;
        bool addOwner;
    }

    // mapping from tx index => owner => bool
    mapping(uint256 => mapping(address => bool)) public isConfirmed;
    mapping(uint256 => mapping(address => bool)) public isConfirmedOwner;
    Transaction[] public transactions;
    TransactionOwner[] public transactionsOwner;

    modifier noReentrant() {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }
    modifier onlyOwner() {
        require(isOwner[msg.sender], "not owner");
        _;
    }

    modifier txExists(uint256 _txIndex) {
        require(_txIndex < transactions.length, "tx does not exist");
        _;
    }
    modifier txExistsOwner(uint256 _txIndex) {
        require(_txIndex < transactionsOwner.length, "tx does not exist");
        _;
    }

    modifier notExecuted(uint256 _txIndex) {
        require(!transactions[_txIndex].executed, "tx already executed");
        _;
    }
    modifier notExecutedOwner(uint256 _txIndex) {
        require(!transactionsOwner[_txIndex].executed, "tx already executed");
        _;
    }

    modifier notConfirmed(uint256 _txIndex) {
        require(!isConfirmed[_txIndex][msg.sender], "tx already confirmed");
        _;
    }
    modifier notConfirmedOwner(uint256 _txIndex) {
        require(
            !isConfirmedOwner[_txIndex][msg.sender],
            "tx already confirmed"
        );
        _;
    }

    constructor(address[] memory _owners, uint256 _numConfirmationsRequired) {
        require(_owners.length > 0, "owners required");
        require(
            _numConfirmationsRequired > 0 &&
                _numConfirmationsRequired <= _owners.length,
            "invalid number of required confirmations"
        );

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];

            require(owner != address(0), "invalid owner");
            require(!isOwner[owner], "owner not unique");

            isOwner[owner] = true;
        }

        numConfirmationsRequired = _numConfirmationsRequired;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    function submitTransaction(
        address _to,
        uint256 _value,
        uint8 _currencyType,
        address _currencyAdrress,
        uint256 ID
    ) public onlyOwner {
        uint256 txIndex = transactions.length;
        require(_currencyType < 3, "This type of currency does not exist");
        transactions.push(
            Transaction({
                to: _to,
                value: _value,
                executed: false,
                numConfirmations: 0,
                currencyType: _currencyType,
                currencyAdrress: _currencyAdrress,
                ID: ID
            })
        );

        emit SubmitTransaction(
            msg.sender,
            txIndex,
            _to,
            _value,
            _currencyAdrress,
            _currencyType
        );
    }

    function submitTransactionOwner(
        address _Owner,
        uint256 _numConfirmations,
        bool _addOwner
    ) public onlyOwner {
        uint256 txIndex = transactions.length;
        transactionsOwner.push(
            TransactionOwner({
                owner: _Owner,
                executed: false,
                numConfirmations: 0,
                addOwner: _addOwner
            })
        );
        emit SubmitTransactionOwner(
            msg.sender,
            txIndex,
            _Owner,
            _numConfirmations,
            _addOwner
        );
    }

    function confirmTransactionOwner(
        uint256 _txIndex
    )
        public
        onlyOwner
        txExistsOwner(_txIndex)
        notExecutedOwner(_txIndex)
        notConfirmedOwner(_txIndex)
    {
        transactionsOwner[_txIndex].numConfirmations += 1;
        isConfirmedOwner[_txIndex][msg.sender] = true;
        emit ConfirmTransaction(msg.sender, _txIndex);
    }

    function confirmTransaction(
        uint256 _txIndex
    )
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
        notConfirmed(_txIndex)
    {
        transactions[_txIndex].numConfirmations += 1;
        isConfirmed[_txIndex][msg.sender] = true;
        emit ConfirmTransaction(msg.sender, _txIndex);
    }

    function executeTransactionOwner(
        uint256 _txIndex
    ) public onlyOwner txExistsOwner(_txIndex) notExecutedOwner(_txIndex) {
        transactionsOwner[_txIndex].executed = true;
        if (transactionsOwner[_txIndex].addOwner == true) {
            require(
                isOwner[transactionsOwner[_txIndex].owner] == false,
                "It's her owner"
            );
            require(
                transactionsOwner[_txIndex].owner != address(0),
                "invalid owner"
            );
            require(
                !isOwner[transactionsOwner[_txIndex].owner],
                "owner not unique"
            );

            isOwner[transactionsOwner[_txIndex].owner] = true;
           emit AddOwner(transactionsOwner[_txIndex].owner);
        } else if (transactionsOwner[_txIndex].addOwner == false) {
            require(
                isOwner[transactionsOwner[_txIndex].owner] == true,
                "It's her owner"
            );
            isOwner[transactionsOwner[_txIndex].owner] = false;
         emit RemoveOwner(transactionsOwner[_txIndex].owner);
        }
    }

    function executeTransaction(
        uint256 _txIndex
    ) public onlyOwner txExists(_txIndex) notExecuted(_txIndex) noReentrant {
        Transaction storage transaction = transactions[_txIndex];

        require(
            transactions[_txIndex].numConfirmations >= numConfirmationsRequired,
            "cannot execute tx"
        );

        transactions[_txIndex].executed = true;

        if (transaction.currencyType == 0) {
            IERC721(transaction.currencyAdrress).safeTransferFrom(
                address(this),
                transaction.to,
                transaction.ID
            );
        } else if (transaction.currencyType == 1) {
            IERC1155(transaction.currencyAdrress).safeTransferFrom(
                address(this),
                transaction.to,
                transaction.ID,
                transaction.value,
                ""
            );
        } else if (transaction.currencyType == 2) {
            IERC20(transaction.currencyAdrress).transfer(
                transaction.to,
                transaction.value
            );
        }

        emit ExecuteTransaction(msg.sender, _txIndex);
    }

    function revokeConfirmation(
        uint256 _txIndex
    ) public onlyOwner txExists(_txIndex) notExecuted(_txIndex) {
        Transaction storage transaction = transactions[_txIndex];

        require(isConfirmed[_txIndex][msg.sender], "tx not confirmed");

        transaction.numConfirmations -= 1;
        isConfirmed[_txIndex][msg.sender] = false;

        emit RevokeConfirmation(msg.sender, _txIndex);
    }

    function revokeConfirmationOwner(
        uint256 _txIndex
    ) public onlyOwner txExistsOwner(_txIndex) notExecutedOwner(_txIndex) {
        require(isConfirmedOwner[_txIndex][msg.sender], "tx not confirmed");

        transactionsOwner[_txIndex].numConfirmations -= 1;
        isConfirmedOwner[_txIndex][msg.sender] = false;

        emit RevokeConfirmation(msg.sender, _txIndex);
    }

    function getTransactionCount() public view returns (uint256) {
        return transactions.length;
    }

    function getTransactionCountOwner() public view returns (uint256) {
        return transactionsOwner.length;
    }

    function getTransaction(
        uint256 _txIndex
    )
        public
        view
        returns (
            address owner,
            uint256 value,
            bool executed,
            uint256 numConfirmations,
            uint8 currencyType,
            address currencyAdrress,
            uint256 ID
        )
    {
        Transaction storage transaction = transactions[_txIndex];

        return (
            transaction.to,
            transaction.value,
            transaction.executed,
            transaction.numConfirmations,
            transaction.currencyType,
            transaction.currencyAdrress,
            transaction.ID
        );
    }

    function getTransactionOwner(
        uint256 _txIndex
    )
        public
        view
        returns (
            address owner,
            bool executed,
            uint256 numConfirmations,
            bool addOwner
        )
    {
        TransactionOwner storage transaction = transactionsOwner[_txIndex];

        return (
            transaction.owner,
            transaction.executed,
            transaction.numConfirmations,
            transaction.addOwner
        );
    }
}
