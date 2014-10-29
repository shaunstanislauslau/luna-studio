---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2014
---------------------------------------------------------------------------
{-# LANGUAGE TupleSections #-}

module Flowbox.Bus.RPC.RPC where

import           Control.Exception          (SomeException)
import qualified Control.Monad.Catch        as Catch
import           Control.Monad.Trans.Either
import           Control.Monad.Trans.State

import Flowbox.Prelude



type RPC s m a = EitherT Error (StateT s m) a


type Error = String


data NoState = NoState
             deriving (Read, Show)


run :: (Catch.MonadCatch m, Monad m, Functor m)
    => RPC s m r -> StateT s m (Either Error r)
run rpc = do
    s <- get
    let handler :: Monad m => SomeException -> m (Either String a)
        handler ex = return $ Left $ "Unhandled exception: " ++ show ex
    result <- lift $ Catch.catch (Right <$> runStateT (runEitherT rpc) s) handler
    case result of
        Left   err      -> {-put s  >> -} return (Left err)
        Right (res, s') -> put s' >> return res
