{-# LANGUAGE GADTs #-}

-- | Transaction metadata conform the wallet specification
module Cardano.Wallet.Kernel.DB.TxMeta.Types (
    -- * Transaction metadata
    TxMeta(..)

    -- ** Lenses
  , txMetaId
  , txMetaAmount
  , txMetaInputs
  , txMetaOutputs
  , txMetaCreationAt
  , txMetaIsLocal
  , txMetaIsOutgoing
  , txMetaWalletId
  , txMetaAccountIx

  -- * Transaction storage
  , MetaDBHandle (..)

  -- * Filtering and sorting primitives
  , AccountFops (..)
  , FilterOperation (..)
  , FilterOrdering (..)
  , Limit (..)
  , Offset (..)
  , Sorting (..)
  , SortCriteria (..)
  , SortDirection (..)

  -- * Domain-specific errors
  , TxMetaStorageError (..)
  , InvariantViolation (..)

  -- * Strict & lenient equalities
  , exactlyEqualTo
  , isomorphicTo
  , txIdIsomorphic

  -- * Internals useful for testing
  , uniqueElements
  , PutReturn (..)
  ) where

import           Universum

import           Control.Lens.TH (makeLenses)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Set as Set
import           Formatting (bprint, build, int, later, shown, string, (%))
import qualified Formatting.Buildable
import           Test.QuickCheck (Arbitrary (..), Gen)

import           Cardano.Wallet.Util (buildIndent, buildList, buildTrunc,
                     buildTuple2)
import qualified Pos.Chain.Txp as Txp
import qualified Pos.Core as Core

import           Cardano.Wallet.Kernel.DB.HdRootId (HdRootId)

import           Test.Pos.Core.Arbitrary ()

{-------------------------------------------------------------------------------
  Transaction metadata
-------------------------------------------------------------------------------}

-- | Transaction metadata

--
-- NOTE: This does /not/ live in the acid-state database (and consequently
-- does not need a 'SafeCopy' instance), because this will grow without bound.
data TxMeta = TxMeta {
      -- | Transaction ID
      _txMetaId         :: Txp.TxId

      -- | Total amount
    , _txMetaAmount     :: Core.Coin

      -- | Transaction inputs
    , _txMetaInputs     :: NonEmpty (Txp.TxId, Word32, Core.Address, Core.Coin)

      -- | Transaction outputs
    , _txMetaOutputs    :: NonEmpty (Core.Address, Core.Coin)

      -- | Transaction creation time
    , _txMetaCreationAt :: Core.Timestamp

      -- | Is this a local transaction?
      --
      -- A transaction is local when /all/ of its inputs and outputs are
      -- to and from addresses owned by this wallet.
    , _txMetaIsLocal    :: Bool

      -- | Is this an outgoing transaction?
      --
      -- A transaction is outgoing when it decreases the wallet's balance.
    , _txMetaIsOutgoing :: Bool

      -- The Wallet that added this Tx.
    , _txMetaWalletId   :: HdRootId

      -- The account index that added this Tx
    , _txMetaAccountIx  :: Word32
    } deriving Show

makeLenses ''TxMeta

instance Buildable TxMeta where
    build txMeta = bprint
        ( "TxMeta (#"%build%" "%string%" "%string%" "%build%"μs)"
        % "\n  amount: "%build
        % "\n  owner: "%buildTrunc build%"/"%build
        % "\n  inputs:     \n"%buildIndent 4 (buildList buildMetaInput)
        % "\n  outputs:    \n"%buildIndent 4 (buildList (buildTuple2 (buildTrunc build) "=>" build))
        )
        (txMeta ^. txMetaId)
        (if txMeta ^. txMetaIsLocal then "local" else "!local")
        (if txMeta ^. txMetaIsOutgoing then "out" else "in")
        (txMeta ^. txMetaCreationAt)
        (txMeta ^. txMetaAmount)
        (txMeta ^. txMetaWalletId)
        (txMeta ^. txMetaAccountIx)
        (txMeta ^. txMetaInputs)
        (txMeta ^. txMetaOutputs)
      where
        buildMetaInput = later $ \(txid, i, addr, coin) ->
            bprint (build%"."%int%" ~ "%buildTrunc build%" "%build)
                txid
                i
                addr
                coin

instance Buildable [TxMeta] where
    build [] = "Empty Tx Metas"
    build xs = bprint ("TxMetas\n" % buildIndent 2 (buildList build)) xs


-- | Strict equality for two 'TxMeta': two 'TxMeta' are equal if they have
-- exactly the same data, and inputs & outputs needs to appear in exactly
-- the same order.
exactlyEqualTo :: TxMeta -> TxMeta -> Bool
exactlyEqualTo t1 t2 =
    and [ t1 ^. txMetaId == t2 ^. txMetaId
        , t1 ^. txMetaAmount == t2 ^. txMetaAmount
        , t1 ^. txMetaInputs  == t2 ^. txMetaInputs
        , t1 ^. txMetaOutputs == t2 ^. txMetaOutputs
        , t1 ^. txMetaCreationAt == t2 ^. txMetaCreationAt
        , t1 ^. txMetaIsLocal == t2 ^. txMetaIsLocal
        , t1 ^. txMetaIsOutgoing == t2 ^. txMetaIsOutgoing
        , t1 ^. txMetaWalletId == t2 ^. txMetaWalletId
        , t1 ^. txMetaAccountIx == t2 ^. txMetaAccountIx
        ]

-- | Lenient equality for two 'TxMeta': two 'TxMeta' are equal if they have
-- the same data, same outputs in the same order and same inputs even if in different order.
-- NOTE: This check might be slightly expensive as it's nlogn in the
-- number of inputs, as it requires sorting.
isomorphicTo :: TxMeta -> TxMeta -> Bool
isomorphicTo t1 t2 =
    and [ t1 ^. txMetaId == t2 ^. txMetaId
        , t1 ^. txMetaAmount == t2 ^. txMetaAmount
        , NonEmpty.sort (t1 ^. txMetaInputs)  == NonEmpty.sort (t2 ^. txMetaInputs)
        , t1 ^. txMetaOutputs == t2 ^. txMetaOutputs
        , t1 ^. txMetaCreationAt == t2 ^. txMetaCreationAt
        , t1 ^. txMetaIsLocal == t2 ^. txMetaIsLocal
        , t1 ^. txMetaIsOutgoing == t2 ^. txMetaIsOutgoing
        , t1 ^. txMetaWalletId == t2 ^. txMetaWalletId
        , t1 ^. txMetaAccountIx == t2 ^. txMetaAccountIx
        ]

-- This means TxMeta have same Inputs and TxId.
txIdIsomorphic :: TxMeta -> TxMeta -> Bool
txIdIsomorphic t1 t2 =
    and [ t1 ^. txMetaId == t2 ^. txMetaId
        , NonEmpty.sort (t1 ^. txMetaInputs)  == NonEmpty.sort (t2 ^. txMetaInputs)
        , t1 ^. txMetaOutputs == t2 ^. txMetaOutputs
        ]

type AccountIx = Word32
type WalletId = HdRootId
-- | Filter Operations on Accounts. This is hiererchical: you can`t have AccountIx without WalletId.
data AccountFops = Everything | AccountFops WalletId (Maybe AccountIx)

data InvariantViolation =
        TxIdInvariantViolated Txp.TxId
        -- ^ When attempting to insert a new 'MetaTx', the TxId
        -- identifying this transaction was already present in the storage,
        -- but with different values (i.e. different inputs/outputs etc)
        -- and this is effectively an invariant violation.
      | UndisputableLookupFailed Text
        -- ^ The db works in a try-catch style: it always first tries to
        -- insert data and if the PrimaryKey is already there, we catch the
        -- exception and do the lookup. This lookup should never fail, because
        -- the db is append only and if it`s found once, it should always
        -- be there.
      deriving Show

-- | A domain-specific collection of things which might go wrong when
-- storing & retrieving 'TxMeta' from a persistent storage.
data TxMetaStorageError =
      InvariantViolated InvariantViolation
    -- ^ One of the invariant was violated.
    | StorageFailure SomeException
    -- ^ The underlying storage failed to fulfill the request.
    deriving Show

instance Exception TxMetaStorageError

instance Buildable TxMetaStorageError where
    build storageErr = bprint shown storageErr

-- | Generates 'NonEmpty' collections which do not contain duplicates.
-- Limit the size to @size@ elements. @size@ should be > 0.
uniqueElements :: (Arbitrary a, Ord a) => Int -> Gen (NonEmpty a)
uniqueElements 0 = error "should have size > 0"
uniqueElements size = do
    (NonEmpty.fromList . Set.toList) <$> (go mempty)
    where
      go st = if (Set.size st == size)
        then return st
        else do
          a <- arbitrary
          go (Set.insert a st)


-- | Basic filtering & sorting types.

newtype Offset = Offset { getOffset :: Integer }

newtype Limit  = Limit  { getLimit  :: Integer }

data SortDirection =
      Ascending
    | Descending

data Sorting = Sorting {
      sbCriteria  :: SortCriteria
    , sbDirection :: SortDirection
    }

data SortCriteria =
      SortByCreationAt
    -- ^ Sort by the creation time of this 'Kernel.TxMeta'.
    | SortByAmount
    -- ^ Sort the 'TxMeta' by the amount of money they hold.

data FilterOperation a =
    NoFilterOp
    -- ^ No filter operation provided
    | FilterByIndex a
    -- ^ Filter by index (e.g. equal to)
    | FilterByPredicate FilterOrdering a
    -- ^ Filter by predicate (e.g. lesser than, greater than, etc.)
    | FilterByRange a a
    -- ^ Filter by range, in the form [from,to]
    | FilterIn [a]
    deriving (Show, Eq)

data FilterOrdering =
      Equal
    | GreaterThan
    | GreaterThanEqual
    | LesserThan
    | LesserThanEqual
    deriving (Show, Eq, Enum, Bounded)

-- This is used mainly for testing and indicates, what happening
-- at the internals of SQlite during a putTxMetaT operation
-- @Tx@ means a new Tx was inserted
-- @Meta@ means the Tx was there but from a different Account, so a new TxMeta entry was created.
-- @No@ means the Tx was there from the same Account. This means nothing happens internally.
data PutReturn = Tx | Meta | No
    deriving (Show, Eq, Enum, Bounded)

instance Buildable PutReturn where
  build ret = bprint shown ret

-- | An opaque handle to the underlying storage, which can be easily instantiated
-- to a more concrete implementation like a Sqlite database, or even a pure
-- K-V store.
data MetaDBHandle = MetaDBHandle {
      closeMetaDB   :: IO ()
    , migrateMetaDB :: IO ()
    , clearMetaDB   :: IO ()
    , deleteTxMetas :: HdRootId -> Maybe Word32 -> IO ()
    , getTxMeta     :: Txp.TxId -> HdRootId -> Word32 -> IO (Maybe TxMeta)
    , putTxMeta     :: TxMeta -> IO ()
    , putTxMetaT    :: TxMeta -> IO PutReturn
    , getAllTxMetas :: IO [TxMeta]
    , getTxMetas    :: Offset -- Pagination: the starting offset of results.
                    -> Limit  -- An upper limit of the length of [TxMeta] returned.
                    -> AccountFops -- Filters on the Account. This may specidy an Account or a Wallet.
                    -> Maybe Core.Address -- Filters on the Addres.
                    -> FilterOperation Txp.TxId -- Filters on the TxId of the Tx.
                    -> FilterOperation Core.Timestamp -- Filters on the creation timestamp of the Tx.
                    -> Maybe Sorting -- Sorting of the results.
                    -> IO ([TxMeta], Maybe Int) -- the result in the form (results, totalEntries).
                                                -- totalEntries may be Nothing, because counting can
                                                -- be an expensive operation.
    }
