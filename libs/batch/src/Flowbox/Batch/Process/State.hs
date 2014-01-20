---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2013
---------------------------------------------------------------------------

module Flowbox.Batch.Process.State where

import Flowbox.Prelude



data State = Running
           | Finished { exitCode :: Int }
           | Killed   { exitCode :: Int }
           deriving (Show)
