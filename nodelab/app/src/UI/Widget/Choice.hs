module UI.Widget.Choice where

import           Utils.PreludePlus             hiding (Choice)
import           Utils.Vector

import           Data.JSString.Text            (lazyTextToJSString)
import           GHCJS.Marshal.Pure            (PFromJSVal (..), PToJSVal (..))
import           GHCJS.Types                   (JSString, JSVal)

import           Object.UITypes
import           Object.Widget
import qualified Object.Widget.Choice          as Model
import qualified Reactive.State.UIRegistry        as UIRegistry

import           UI.Generic                    (whenChanged)
import qualified UI.Generic                    as UI
import qualified UI.Registry                   as UI
import           UI.Widget                     (UIWidget (..))
import qualified UI.Widget                     as Widget

newtype Choice = Choice JSVal deriving (PToJSVal, PFromJSVal)

instance UIWidget Choice

foreign import javascript unsafe "new Group($1)" create' :: Int -> IO Choice

create :: WidgetId -> Model.Choice -> IO Choice
create oid model = do
    widget <- create' oid
    UI.setWidgetPosition (model ^. widgetPosition) widget
    return widget

instance UIDisplayObject Model.Choice where
    createUI parentId id model = do
        widget <- create id model
        parent <- UI.lookup parentId :: IO Widget.GenericWidget
        UI.register id widget
        Widget.add widget parent

    updateUI id old model = return ()