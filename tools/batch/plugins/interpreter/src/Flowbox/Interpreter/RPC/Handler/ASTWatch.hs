---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2014
---------------------------------------------------------------------------

module Flowbox.Interpreter.RPC.Handler.ASTWatch where

import Control.Monad.Trans.Class (lift)

import           Flowbox.Bus.RPC.RPC                                                               (RPC)
import qualified Flowbox.Data.SetForest                                                            as SetForest
import           Flowbox.Interpreter.Proto.CallPoint                                               ()
import           Flowbox.Interpreter.Proto.CallPointPath                                           ()
import qualified Flowbox.Interpreter.Session.AST.Executor                                          as Executor
import qualified Flowbox.Interpreter.Session.AST.WatchPoint                                        as WatchPoint
import qualified Flowbox.Interpreter.Session.Cache.Invalidate                                      as Invalidate
import qualified Flowbox.Interpreter.Session.Data.CallPoint                                        as CallPoint
import           Flowbox.Interpreter.Session.SessionT                                              (SessionT (SessionT))
import           Flowbox.Prelude
import           Flowbox.System.Log.Logger                                                         hiding (error)
import           Flowbox.Tools.Serialize.Proto.Conversion.Basic
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Data.Add.Request               as AddData
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Data.Add.Update                as AddData
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Data.Modify.Classes.Request    as ModifyDataClasses
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Data.Modify.Classes.Update     as ModifyDataClasses
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Data.Modify.Cls.Request        as ModifyDataCls
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Data.Modify.Cls.Update         as ModifyDataCls
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Data.Modify.Cons.Request       as ModifyDataCons
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Data.Modify.Cons.Update        as ModifyDataCons
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Data.Modify.Methods.Request    as ModifyDataMethods
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Data.Modify.Methods.Update     as ModifyDataMethods
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Function.Add.Request           as AddFunction
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Function.Add.Update            as AddFunction
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Function.Modify.Inputs.Request as ModifyFunctionInputs
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Function.Modify.Inputs.Update  as ModifyFunctionInputs
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Function.Modify.Name.Request   as ModifyFunctionName
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Function.Modify.Name.Update    as ModifyFunctionName
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Function.Modify.Output.Request as ModifyFunctionOutput
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Function.Modify.Output.Update  as ModifyFunctionOutput
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Function.Modify.Path.Request   as ModifyFunctionPath
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Function.Modify.Path.Update    as ModifyFunctionPath
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Get.Request                    as Definitions
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Get.Status                     as Definitions
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Module.Add.Request             as AddModule
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Module.Add.Update              as AddModule
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Module.Modify.Cls.Request      as ModifyModuleCls
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Module.Modify.Cls.Update       as ModifyModuleCls
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Module.Modify.Fields.Request   as ModifyModuleFields
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Module.Modify.Fields.Update    as ModifyModuleFields
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Module.Modify.Imports.Request  as ModifyModuleImports
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Module.Modify.Imports.Update   as ModifyModuleImports
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Remove.Request                 as Remove
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Remove.Update                  as Remove
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Resolve.Request                as ResolveDefinition
import qualified Generated.Proto.ProjectManager.Project.Library.AST.Resolve.Status                 as ResolveDefinition
import qualified Generated.Proto.ProjectManager.Project.Store.Status                               as Store




logger :: LoggerIO
logger = getLoggerIO "Flowbox.Interpreter.RPC.Handler.ASTWatch"


test :: Definitions.Status -> RPC SessionT ()
test (Definitions.Status tfocus mtmaxDepth tbc tlibID tprojectID) = do
    print "!!!"


test2 :: Store.Status -> RPC SessionT ()
test2 _ = do
    print "!!!222"

test3 :: Store.Status -> RPC SessionT Store.Status
test3 r = do
    print "!!!333"
    return r

