---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2014
---------------------------------------------------------------------------
{-# LANGUAGE DeriveDataTypeable #-}

module Flowbox.Graphics.Color.CMYK where

import Data.Typeable

import Flowbox.Prelude



data CMYK a = CMYK { cmykC :: a, cmykM :: a, cmykY :: a, cmykK :: a } deriving (Show,Typeable)
