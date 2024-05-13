// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/interfaces/IERC1155.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract MultiSigWallet is ERC721Holder, ERC1155Holder {
    bool internal locked;
    uint256 public NumberOfOwners;
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
        bool addOwner
    );
    event SubmitTransactionNewNumConfirmations(
        uint indexed NewNumConfirmations,
        uint256 indexed txIndex,
        address ownerSuggested
    );
    event ConfirmTransaction(address indexed owner, uint256 indexed txIndex);
    event RevokeConfirmation(address indexed owner, uint256 indexed txIndex);
    event ExecuteTransaction(address indexed owner, uint256 indexed txIndex);

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
    struct TransactionNewNumConfirmations {
        uint256 NewNumConfirmations;
        bool executed;
        uint256 numConfirmations;
    }
    // mapping from tx index => owner => bool
    mapping(uint256 => mapping(address => bool)) public isConfirmed;
    mapping(uint256 => mapping(address => bool)) public isConfirmedOwner;
    mapping(uint256 => mapping(address => bool))
        public isConfirmedNewNumConfirmations;

    Transaction[] public transactions;
    TransactionOwner[] public transactionsOwner;
    TransactionNewNumConfirmations[] public transactionNewNumConfirmations;
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

    modifier txExists(uint256 _txIndex, int8 operation) {
        if (operation == 1) {
            require(_txIndex < transactions.length, "tx does not exist");
        } else if (operation == 2) {
            require(_txIndex < transactionsOwner.length, "tx does not exist");
        } else if (operation == 3) {
            require(
                _txIndex < transactionNewNumConfirmations.length,
                "tx does not exist"
            );
        }

        _;
    }

    modifier notExecuted(uint256 _txIndex, int8 operation) {
        if (operation == 1) {
            require(!transactions[_txIndex].executed, "tx already executed");
        } else if (operation == 2) {
            require(
                !transactionsOwner[_txIndex].executed,
                "tx already executed"
            );
        } else if (operation == 3) {
            require(
                !transactionNewNumConfirmations[_txIndex].executed,
                "tx already executed"
            );
        }
        _;
    }

    modifier notConfirmed(uint256 _txIndex, int8 operation) {
        if (operation == 1) {
            require(!isConfirmed[_txIndex][msg.sender], "tx already confirmed");
        } else if (operation == 2) {
            require(
                !isConfirmedOwner[_txIndex][msg.sender],
                "tx already confirmed"
            );
        } else if (operation == 3) {
            require(
                !isConfirmedNewNumConfirmations[_txIndex][msg.sender],
                "tx already confirmed"
            );
        }
        _;
    }
    modifier confirmed(uint256 _txIndex, int8 operation) {
        if (operation == 1) {
            require(isConfirmed[_txIndex][msg.sender], "tx not confirmed");
        } else if (operation == 2) {
            require(isConfirmedOwner[_txIndex][msg.sender], "tx not confirmed");
        } else if (operation == 3) {
            require(
                isConfirmedNewNumConfirmations[_txIndex][msg.sender],
                "tx not confirmed"
            );
        }
        _;
    }
    modifier numRequired(uint256 _txIndex, int8 operation) {
        if (operation == 1) {
            require(
                transactions[_txIndex].numConfirmations >=
                    numConfirmationsRequired,
                "cannot execute tx"
            );
        } else if (operation == 2) {
            require(
                transactionsOwner[_txIndex].numConfirmations >=
                    numConfirmationsRequired,
                "cannot execute tx"
            );
        } else if (operation == 3) {
            require(
                transactionNewNumConfirmations[_txIndex].numConfirmations >=
                    numConfirmationsRequired,
                "cannot execute tx"
            );
        }
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
        NumberOfOwners = _owners.length;
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
        bool _addOwner
    ) public onlyOwner {
        uint256 txIndex = transactions.length;
        if (_addOwner == true) {
            require(!isOwner[_Owner], "It's her owner");
            require(_Owner != address(0), "invalid owner");
        } else {
            require(isOwner[_Owner], "It's not owner");
        }
        transactionsOwner.push(
            TransactionOwner({
                owner: _Owner,
                executed: false,
                numConfirmations: 0,
                addOwner: _addOwner
            })
        );
        emit SubmitTransactionOwner(msg.sender, txIndex, _Owner, _addOwner);
    }

    function submitTransactionNewNumConfirmations(
        uint256 NewNumConfirmations
    ) public onlyOwner {
        require(
            NewNumConfirmations > 0 &&
                NewNumConfirmations <= NumberOfOwners &&
                NewNumConfirmations != numConfirmationsRequired,
            "invalid number of required confirmations"
        );
        uint256 txIndex = transactionNewNumConfirmations.length;
        transactionNewNumConfirmations.push(
            TransactionNewNumConfirmations({
                NewNumConfirmations: NewNumConfirmations,
                executed: false,
                numConfirmations: 0
            })
        );
        emit SubmitTransactionNewNumConfirmations(
            NewNumConfirmations,
            txIndex,
            msg.sender
        );
    }

    function confirmTransactionNewNumConfirmations(
        uint256 _txIndex
    )
        public
        onlyOwner
        txExists(_txIndex, 3)
        notExecuted(_txIndex, 3)
        notConfirmed(_txIndex, 3)
    {
        transactionNewNumConfirmations[_txIndex].numConfirmations += 1;
        isConfirmedNewNumConfirmations[_txIndex][msg.sender] = true;
        emit ConfirmTransaction(msg.sender, _txIndex);
    }

    function confirmTransactionOwner(
        uint256 _txIndex
    )
        public
        onlyOwner
        txExists(_txIndex, 2)
        notExecuted(_txIndex, 2)
        notConfirmed(_txIndex, 2)
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
        txExists(_txIndex, 1)
        notExecuted(_txIndex, 1)
        notConfirmed(_txIndex, 1)
    {
        transactions[_txIndex].numConfirmations += 1;
        isConfirmed[_txIndex][msg.sender] = true;
        emit ConfirmTransaction(msg.sender, _txIndex);
    }

    function executeTransactionOwner(
        uint256 _txIndex
    )
        public
        onlyOwner
        txExists(_txIndex, 2)
        notExecuted(_txIndex, 2)
        numRequired(_txIndex, 2)
    {
        transactionsOwner[_txIndex].executed = true;

        if (transactionsOwner[_txIndex].addOwner == true) {
            NumberOfOwners += 1;
            isOwner[transactionsOwner[_txIndex].owner] = true;
        } else if (transactionsOwner[_txIndex].addOwner == false) {
            NumberOfOwners -= 1;

            isOwner[transactionsOwner[_txIndex].owner] = false;
        }
        emit ExecuteTransaction(msg.sender, _txIndex);
    }

    function executeTransactionNewNumConfirmations(
        uint256 _txIndex
    )
        public
        onlyOwner
        txExists(_txIndex, 3)
        notExecuted(_txIndex, 3)
        numRequired(_txIndex, 3)
    {
        transactionNewNumConfirmations[_txIndex].executed = true;
        numConfirmationsRequired = transactionNewNumConfirmations[_txIndex]
            .NewNumConfirmations;
        emit ExecuteTransaction(msg.sender, _txIndex);
    }

    function executeTransaction(
        uint256 _txIndex
    )
        public
        payable
        onlyOwner
        txExists(_txIndex, 1)
        notExecuted(_txIndex, 1)
        noReentrant
        numRequired(_txIndex, 1)
    {
        Transaction storage transaction = transactions[_txIndex];

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
                "0x676574"
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
    )
        public
        onlyOwner
        txExists(_txIndex, 1)
        notExecuted(_txIndex, 1)
        confirmed(_txIndex, 1)
    {
        Transaction storage transaction = transactions[_txIndex];

        transaction.numConfirmations -= 1;
        isConfirmed[_txIndex][msg.sender] = false;

        emit RevokeConfirmation(msg.sender, _txIndex);
    }

    function revokeConfirmationNewNumConfirmations(
        uint256 _txIndex
    )
        public
        onlyOwner
        txExists(_txIndex, 3)
        confirmed(_txIndex, 3)
        notExecuted(_txIndex, 3)
    {
        TransactionNewNumConfirmations
            storage transaction = transactionNewNumConfirmations[_txIndex];

        transaction.numConfirmations -= 1;
        isConfirmed[_txIndex][msg.sender] = false;

        emit RevokeConfirmation(msg.sender, _txIndex);
    }

    function revokeConfirmationOwner(
        uint256 _txIndex
    )
        public
        onlyOwner
        txExists(_txIndex, 2)
        notExecuted(_txIndex, 2)
        confirmed(_txIndex, 2)
    {
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

    function getTransactionCountNewNumConfirmations()
        public
        view
        returns (uint256)
    {
        return transactionNewNumConfirmations.length;
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

    function getTransactionNewNumConfirmations(
        uint256 _txIndex
    )
        public
        view
        returns (
            uint256 NewNumConfirmations,
            bool executed,
            uint256 numConfirmations
        )
    {
        TransactionNewNumConfirmations
            storage transaction = transactionNewNumConfirmations[_txIndex];

        return (
            transaction.NewNumConfirmations,
            transaction.executed,
            transaction.numConfirmations
        );
    }
}
