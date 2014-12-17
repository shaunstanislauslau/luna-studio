---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Flowbox Team <contact@flowbox.io>, 2014
-- Proprietary and confidential
-- Unauthorized copying of this file, via any medium is strictly prohibited
---------------------------------------------------------------------------
{-# LANGUAGE RankNTypes #-}

module Luna.Interpreter.Session.Memory.Manager where

import qualified Control.Monad.Ghc          as MGHC
import           Control.Monad.State
import           Control.Monad.Trans.Either

import Flowbox.Prelude
import Luna.Interpreter.Session.Data.CallPointPath (CallPointPath)
import Luna.Interpreter.Session.Data.VarName       (VarName)
import Luna.Interpreter.Session.Env.Env            (Env)
import Luna.Interpreter.Session.Error              (Error)
import Luna.Interpreter.Session.Memory.Data.Status (Status)



type SessionST m   = StateT (Env m) MGHC.Ghc
type Session   m a = EitherT Error (SessionST m) a


class Default mm => MemoryManager mm where
    reportUse        :: CallPointPath -> VarName -> Session mm ()
    reportUseMany    :: [(CallPointPath, VarName)] -> Session mm ()
    reportDelete     :: CallPointPath -> VarName   -> Session mm ()
    reportDeleteMany :: [(CallPointPath, VarName)] -> Session mm ()
    clean            :: Status        -> Session mm ()
    cleanIfNeeded    :: Session mm ()

    reportUseMany []    = return ()
    reportUseMany (h:t) = uncurry reportUse h >> reportUseMany t

    reportDeleteMany []    = return ()
    reportDeleteMany (h:t) = uncurry reportDelete h >> reportDeleteMany t
