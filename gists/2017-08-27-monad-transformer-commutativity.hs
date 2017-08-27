#!/usr/bin/env stack
-- stack --resolver lts-9.1 --install-ghc exec ghci --package transformers

import Control.Monad.Trans.Except (Except(..), ExceptT(..))
import qualified Control.Monad.Trans.Except as Except
import Control.Monad.Trans.Identity (IdentityT(..))
import qualified Control.Monad.Trans.Identity as Identity
import Control.Monad.Trans.Maybe (MaybeT(..))
import qualified Control.Monad.Trans.Maybe as Maybe
import Control.Monad.Trans.RWS (RWS(..), RWST(..))
import qualified Control.Monad.Trans.RWS as RWS
import Control.Monad.Trans.Reader (Reader(..), ReaderT(..))
import qualified Control.Monad.Trans.Reader as Reader
import Control.Monad.Trans.State (State(..), StateT(..))
import qualified Control.Monad.Trans.State as State
import Control.Monad.Trans.Writer (Writer(..), WriterT(..))
import qualified Control.Monad.Trans.Writer as Writer
import Data.Functor.Identity (Identity(..))
import qualified Data.Functor.Identity as Identity
import Data.Maybe (Maybe(..))
import qualified Data.Maybe as Maybe

plainIdentity :: Identity a -> a
plainIdentity m = runIdentity m

plainReader :: Reader r a -> r -> a
plainReader m = Reader.runReader m

plainWriter :: Writer w a -> (a, w)
plainWriter m = Writer.runWriter m

plainState :: State s a -> s -> (a, s)
plainState m s = State.runState m s

plainMaybe :: Maybe a -> b -> (a -> b) -> b
plainMaybe m d f = maybe d f m

plainExcept :: Except e a -> Either e a
plainExcept m = Except.runExcept m

plainRWS :: RWS r w s a -> r -> s -> (a, s, w)
plainRWS m r s = RWS.runRWS m r s

identityIdentity :: IdentityT Identity a -> a
identityIdentity m = runIdentity (Identity.runIdentityT m)

identityReader :: IdentityT (Reader r) a -> r -> a
identityReader m r = Reader.runReader (Identity.runIdentityT m) r

identityWriter :: IdentityT (Writer w) a -> (a, w)
identityWriter m = Writer.runWriter (Identity.runIdentityT m)

identityState :: IdentityT (State s) a -> s -> (a, s)
identityState m s = State.runState (Identity.runIdentityT m) s

identityMaybe :: IdentityT Maybe a -> b -> (a -> b) -> b
identityMaybe m d f = maybe d f (Identity.runIdentityT m)

identityExcept :: IdentityT (Except e) a -> Either e a
identityExcept m = Except.runExcept (Identity.runIdentityT m)

identityRWS :: IdentityT (RWS r w s) a -> r -> s -> (a, s, w)
identityRWS m r s = RWS.runRWS (Identity.runIdentityT m) r s

readerIdentity :: ReaderT r Identity a -> r -> a
readerIdentity m r = runIdentity (Reader.runReaderT m r)

readerReader :: ReaderT r (Reader r') a -> r -> r' -> a
readerReader m r r' = Reader.runReader (Reader.runReaderT m r) r'

readerWriter :: ReaderT r (Writer w) a -> r -> (a, w)
readerWriter m r = Writer.runWriter (Reader.runReaderT m r)

readerState :: ReaderT r (State s) a -> r -> s -> (a, s)
readerState m r s = State.runState (Reader.runReaderT m r) s

readerMaybe :: ReaderT r Maybe a -> r -> b -> (a -> b) -> b
readerMaybe m r d f = maybe d f (Reader.runReaderT m r)

readerExcept :: ReaderT r (Except e) a -> r -> Either e a
readerExcept m r = Except.runExcept (Reader.runReaderT m r)

readerRWS :: ReaderT r (RWS r' w s) a -> r -> r' -> s -> (a, s, w)
readerRWS m r r' s = RWS.runRWS (Reader.runReaderT m r) r' s

writerIdentity :: WriterT w Identity a -> (a, w)
writerIdentity m = runIdentity (Writer.runWriterT m)

writerReader :: WriterT w (Reader r) a -> r -> (a, w)
writerReader m r = Reader.runReader (Writer.runWriterT m) r

writerWriter :: WriterT w (Writer w') a -> ((a, w), w')
writerWriter m = Writer.runWriter (Writer.runWriterT m)

writerState :: WriterT w (State s) a -> s -> ((a, w), s)
writerState m s = State.runState (Writer.runWriterT m) s

writerMaybe :: WriterT w Maybe a -> (b, w') -> ((a, w) -> (b, w')) -> (b, w')
writerMaybe m d f = maybe d f (Writer.runWriterT m)

writerExcept :: WriterT w (Except e) a -> Either e (a, w)
writerExcept m = Except.runExcept (Writer.runWriterT m)

writeRWS :: WriterT w (RWS r w' s) a -> r -> s -> ((a, w), s, w')
writeRWS m r s = RWS.runRWS (Writer.runWriterT m) r s

stateIdentity :: StateT s Identity a -> s -> (a, s)
stateIdentity m s = runIdentity (State.runStateT m s)

stateReader :: StateT s (Reader r) a -> s -> r -> (a, s)
stateReader m s r = Reader.runReader (State.runStateT m s) r

stateWriter :: StateT s (Writer w) a -> s -> ((a, s), w)
stateWriter m s = Writer.runWriter (State.runStateT m s)

stateState :: StateT s (State s') a -> s -> s' -> ((a, s), s')
stateState m s s' = State.runState (State.runStateT m s) s'

stateMaybe :: StateT s Maybe a -> s -> (b, s') -> ((a, s) -> (b, s')) -> (b, s')
stateMaybe m s d f = maybe d f (State.runStateT m s)

stateExcept :: StateT s (Except e) a -> s -> Either e (a, s)
stateExcept m s = Except.runExcept (State.runStateT m s)

stateRWS :: StateT s (RWS r w s') a -> s -> r -> s' -> ((a, s), s', w)
stateRWS m s r s' = RWS.runRWS (State.runStateT m s) r s'

maybeIdentity :: MaybeT Identity a -> Maybe a
maybeIdentity m = runIdentity (Maybe.runMaybeT m)

maybeReader :: MaybeT (Reader r) a -> r -> Maybe a
maybeReader m r = Reader.runReader (Maybe.runMaybeT m) r

maybeWriter :: MaybeT (Writer w) a -> (Maybe a, w)
maybeWriter m = Writer.runWriter (Maybe.runMaybeT m)

maybeState :: MaybeT (State s) a -> s -> (Maybe a, s)
maybeState m s = State.runState (Maybe.runMaybeT m) s

maybeMaybe :: MaybeT Maybe a -> (Maybe b) -> (Maybe a -> Maybe b) -> Maybe b
maybeMaybe m d f = maybe d f (Maybe.runMaybeT m)

maybeExcept :: MaybeT (Except e) a -> Either e (Maybe a)
maybeExcept m = Except.runExcept (Maybe.runMaybeT m)

maybeRWS :: MaybeT (RWS r w s) a -> r -> s -> ((Maybe a), s, w)
maybeRWS m r s = RWS.runRWS (Maybe.runMaybeT m) r s

exceptIdentity :: ExceptT e Identity a -> Either e a
exceptIdentity m = runIdentity (Except.runExceptT m)

exceptReader :: ExceptT e (Reader r) a -> r -> Either e a
exceptReader m r = Reader.runReader (Except.runExceptT m) r

exceptWriter :: ExceptT e (Writer w) a -> (Either e a, w)
exceptWriter m = Writer.runWriter (Except.runExceptT m)

exceptState :: ExceptT e (State s) a -> s -> (Either e a, s)
exceptState m s = State.runState (Except.runExceptT m) s

exceptMaybe :: ExceptT e Maybe a -> Either e' b -> (Either e a -> Either e' b) -> Either e' b
exceptMaybe m d f = maybe d f (Except.runExceptT m)

exceptExcept :: ExceptT e (Except e') a -> Either e' (Either e a)
exceptExcept m = Except.runExcept (Except.runExceptT m)

exceptRWS :: ExceptT e (RWS r w s) a -> r -> s -> (Either e a, s, w)
exceptRWS m r s = RWS.runRWS (Except.runExceptT m) r s

rwsIdentity :: RWST r w s Identity a -> r -> s -> (a, s, w)
rwsIdentity m r s = runIdentity (RWS.runRWST m r s)

rwsReader :: RWST r w s (Reader r') a -> r -> s -> r' -> (a, s, w)
rwsReader m r s r' = Reader.runReader (RWS.runRWST m r s) r'

rwsWriter :: RWST r w s (Writer w') a -> r -> s -> ((a, s, w), w')
rwsWriter m r s = Writer.runWriter (RWS.runRWST m r s)

rwsState :: RWST r w s (State s') a -> r -> s -> s' -> ((a, s, w), s')
rwsState m r s s' = State.runState (RWS.runRWST m r s) s'

rwsMaybe :: RWST r w s Maybe a -> r -> s -> (b, s', w') -> ((a, s, w) -> (b, s', w')) -> (b, s', w')
rwsMaybe m r s d f = maybe d f (RWS.runRWST m r s)

rwsExcept :: RWST r w s (Except e) a -> r -> s -> Either e (a, s, w)
rwsExcept m r s = Except.runExcept (RWS.runRWST m r s)

rwsRws :: RWST r w s (RWS r' w' s') a -> r -> s -> r' -> s' -> ((a, s, w), s', w')
rwsRws m r s r' s' = RWS.runRWS (RWS.runRWST m r s) r' s'
