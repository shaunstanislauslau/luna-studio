---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2014
---------------------------------------------------------------------------

module Luna.DEP.AST.Import(
    Import(..),
) where

import Flowbox.Data.Path
import Flowbox.Prelude



data Import = Import {path :: Path, name :: String} deriving (Show)

