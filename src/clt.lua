--[[
    Filename:    clt.lua
    Author:      chenhailong
    Datetime:    2018-11-30 20:25:51
    Description: Command line tool
--]]
module("clt", package.seeall)

local function classMeta(cls)
    return {
        __metatable = "private",
        __call = function (cls, ...)
            local obj = setmetatable({__class__ = cls,}, {
                __index = cls,
            })
            obj:initialize(...)
            return obj
        end,
        __index = function (t, k)
            local super = rawget(cls, "__super__")
            return super and super[k]
        end,
    }
end

--- @class clt.Object
local Object = {__name__ = "Object"}
Object = setmetatable(Object, classMeta(Object))

function Object:initialize()
end

function Object:subclass(name)
    local cls = {
        __name__ = name,
        __super__ = self,
    }
    return setmetatable(cls, classMeta(cls))
end

local function class(name, superClass)
    return (superClass or Object):subclass(name)
end

--[[
function Object:super()
    local info = debug.getinfo(2, "nf")
    local name, caller = info.name, info.func
    local cls = self.__class__
    while cls~=nil do
        if rawget(cls, name)==caller then
            return cls.__super__
        end
        cls = cls.__super__
    end
    return nil
end
--]]

--------------------------------------------------------------------------------
--- options parser

local OPT_ERROR_INVALID_OPTION = "INVALID_OPTION"
local OPT_ERROR_MISSING_OPTION = "MISSING_OPTION"
local OPT_ERROR_INADEQUATE_ARGS = "INADEQUATE_ARGS"

--- @class clt.OptionConfig
--- @field 1 string @ Alias for `opt` field.
--- @field opt string @ The option definition in these forms:
---             "-v", "-v, --version", "-s, --shout / --no-shout"
--- @field name string @ [Optional] The variable name for the option value.
--- @field is_flag boolean @ [Optional] Whether this option is a boolean flag.
---             If there is a "/" in the `opt`, this field will be ignored and the
---             option will always be treated as a boolean flag.
--- @field required boolean @ [Optional] Whether this option is required.
--- @field multiple boolean @ [Optional] Whether this option can be provided multiple times.
--- @field nargs integer @ [Optional] The number of option arguments. Default value is 1.
--- @field default @ [Optional] The default value of this option.
--- @field help string @ [Optional] The description of this option displayed in the help page.
--- @field metavar string @ [Optional] Used for changing the meta variable in the help page.


--- @class clt.OptionConfigs : clt.OptionConfig[]
--- @field metavar string @ [Optional] Used for changing the meta variable in the help page.


--- @class clt.ArgumentConfig
--- @field name string @ [Optional] The variable name for the argument value.
--- @field nargs integer @ [Optional] The number of arguments. Default value is 1.
---             If it is set to -1, then an unlimited number of arguments is accepted.
--- @field help string @ [Optional] The description of this argument displayed in the help page.
--- @field metavar string @ [Optional] Used for changing the meta variable in the help page.


--- @class clt.ArgumentConfigs : clt.ArgumentConfig[]
--- @field metavar string @ [Optional] Used for changing the meta variable in the help page.


--- @class clt.OptionsParser
local OptionsParser = class("OptionsParser")

--- @desc Constructor of OptionsParser.
--- @param optionsConfig clt.OptionConfigs @ [Optional] Configurations for all options.
--- @param argsConfig clt.ArgumentConfigs @ [Optional] Configurations for arguments.
function OptionsParser:initialize(optionsConfig, argsConfig)
    OptionsParser.__super__.initialize(self)

    self._optionsConfig = {}
    if optionsConfig~=nil then
        for i, optCfg in ipairs(optionsConfig) do
            self._optionsConfig[i] = self:_parseOptConfig(optCfg)
        end
        self._optionsMetavar = optionsConfig.metavar or "[OPTIONS]"
    else
        self._optionsMetavar = ""
    end

    self._argsConfig = {}
    if argsConfig~=nil then
        local metavars = argsConfig.metavar==nil and {} or nil
        local minFollows = 0
        for i = #argsConfig, 1, -1 do
            local arg = self:_parseArgConfig(argsConfig[i])
            if arg.nargs<0 then
                assert(minFollows>=0, "Arguments CANNOT have two nargs < 0")
                arg.nargs = -1 - minFollows
                minFollows = -1
            elseif minFollows>=0 then
                minFollows = minFollows + arg.nargs
            end
            self._argsConfig[i] = arg
            if metavars~=nil then
                metavars[#metavars + 1] = arg.metavar
            end
        end
        self._argumentsMetavar = argsConfig.metavar or table.concat(metavars, " ")
    else
        self._argumentsMetavar = ""
    end
end

function OptionsParser:getOptionsMetavar()
    return self._optionsMetavar
end

function OptionsParser:printOptionsDescription(title, indents, print)
    if #self._optionsConfig>0 then
        local lines, width = {}, 19
        local format = string.format
        for i, opt in ipairs(self._optionsConfig) do
            local metavar = opt.opt .. " " .. opt.metavar
            local len = metavar:len()
            if len >= width then width = 4*math.floor((len+3)/4) - 1 end
            lines[#lines + 1] = {metavar, opt.help or ""}
        end
        if #lines > 0 then
            print(title)
            local fmt = "%s%-" .. width .. "s  %s"
            for i = 1, #lines do
                local line = lines[i]
                print(format(fmt, indents, line[1], line[2]))
            end
        end
    end
end

function OptionsParser:getArgumentsMetavar()
    return self._argumentsMetavar
end

function OptionsParser:printArgumentsDescription(title, indents, print)
    if #self._argsConfig>0 then
        local lines, width = {}, 19
        local format = string.format
        for i, arg in ipairs(self._argsConfig) do
            local metavar = arg.metavar
            local len = metavar:len()
            if len >= width then width = 4*math.floor((len+3)/4) - 1 end
            if arg.help~=nil then
                lines[#lines + 1] = {metavar, arg.help}
            end
        end
        if #lines > 0 then
            print(title)
            local fmt = "%s%-" .. width .. "s  %s"
            for i = 1, #lines do
                local line = lines[i]
                print(format(fmt, indents, line[1], line[2]))
            end
        end
    end
end

--- #private
function OptionsParser:_parseOptConfig(optCfg)
    local name = optCfg.name
    local is_flag = optCfg.is_flag
    local optString = optCfg.opt or optCfg[1]
    local namesString = optString:gsub("%s", "")
    local ssp = namesString:find("/") -- switch separator position
    if ssp~=nil then is_flag = true end
    local opts, opts_on, opts_off
    if is_flag then
        if ssp~=nil then
            opts_on, opts_off = namesString:sub(1, ssp-1), namesString:sub(ssp+1)
        else
            opts_on, opts_off = namesString, ""
        end
        opts_on, name = self:_parseOptConfigNames(opts_on, name)
        opts_off, name = self:_parseOptConfigNames(opts_off, name)
    else
        opts, name = self:_parseOptConfigNames(namesString, name)
    end

    local finalConfig = {
        name = name,
        opt = optString,
        opts = opts,
        opts_on = opts_on,
        opts_off = opts_off,
        required = optCfg.required and true or false,
        -- multiple = optCfg.multiple and true or false,
        help = optCfg.help or nil,
    }
    if is_flag then
        finalConfig.nargs = 0
        finalConfig.default = optCfg.default and true or false
        finalConfig.metavar = ""
    else
        assert(optCfg.nargs==nil or optCfg.nargs>0, "Option CANNOT have nargs <= 0")
        finalConfig.nargs = optCfg.nargs or 1
        finalConfig.default = optCfg.default
        if optCfg.metavar~=nil then
            finalConfig.metavar = optCfg.metavar
        else
            finalConfig.metavar = finalConfig.nargs==1 and "<VALUE>" or "<VALUES...>"
        end
    end
    if optCfg.multiple then
        finalConfig.multiple = true
        assert(finalConfig.default==nil or type(finalConfig.default)=="table",
               "Default value for multiple option MUST be an array")
    else
        finalConfig.multiple = false
    end
    return finalConfig
end

--- #private
function OptionsParser:_parseOptConfigNames(namesString, varName)
    local pattern = "(%-+)([%w_%-]*),*"
    local opts = {}
    local tmpName = varName==nil and "" or nil
    local s, e, prefix, name = namesString:find(pattern)
    while prefix~=nil do
        local optName = prefix .. name
        opts[#opts + 1] = optName
        opts[optName] = true
        if tmpName~=nil and tmpName:len()<name:len() then
            tmpName = name
        end
        s, e, prefix, name = namesString:find(pattern, e+1)
    end
    return opts, tmpName or varName
end

--- #private
function OptionsParser:_parseArgConfig(argCfg)
    local name = argCfg.name
    assert(name~=nil, "Argument must have a name")
    local nargs = argCfg.nargs or 1
    local metavar = argCfg.metavar
    if metavar==nil then
        metavar = string.upper(name)
        if nargs>1 then metavar = "[" .. metavar .. "...]" end
    end
    local finalConfig = {
        name = name,
        nargs = nargs,
        metavar = metavar,
        help = argCfg.help or nil,
    }
    return finalConfig
end

--- @param tokens string[] @ Array of argument tokens.
--- @param index integer @ Index of next argument token.
--- @return table @ The context for parsing options.
function OptionsParser:startParsing(tokens, index)
    local context = {}

    context.optionValues = {}
    context.arguments = {}

    -- fill default option values
    local optionValues = context.optionValues
    local multipleOptionDefaults = {}
    context._multipleOptionDefaults = multipleOptionDefaults
    for i, opt in ipairs(self._optionsConfig) do
        if opt.multiple then
            local valueArray = {}
            if opt.default~=nil and #opt.default>0 then
                for i, v in ipairs(opt.default) do valueArray[i] = v end
                multipleOptionDefaults[valueArray] = true
            end
            optionValues[opt.name] = valueArray
        else
            optionValues[opt.name] = opt.default
        end
    end

    context.finishOnError = true
    context.error = nil -- first error
    context.last_error = nil -- last error
    function context:appendError(err)
        if err==nil then return end
        if self.last_error~=nil then
            self.last_error.next = err
        else
            self.error = err
        end
        self.last_error = err
        if self.finishOnError then
            self.finished = true
        end
    end

    return context
end

--- @param context table @ The context returned by `startParsing()`.
--- @return boolean @ Indicate whether the parsing is success.
function OptionsParser:finishParsing(context)
    if context.finished then
        return context.error~=nil
    end
    local optionValues = context.optionValues
    for i, opt in ipairs(self._optionsConfig) do
        local name = opt.name
        local value = optionValues[name]
        if opt.required and (value==nil or (opt.multiple and #value==0)) then
            context:appendError({
                                    type = OPT_ERROR_MISSING_OPTION,
                                    opt = opt,
                                })
            if context.finished then
                break
            end
        end
    end
    context.finished = true
    return context.error~=nil
end

--- @param context table @ The context returned by `startParsing()`.
--- @param tokens string[] @ Array of argument tokens.
--- @param index integer @ Index of next argument token.
--- @return integer, string, any @ Next token index, option name and value.
---             If next token is not an option, the name and value will be nil.
function OptionsParser:parseNextOption(context, tokens, index)
    if context.finished then
        return index, nil, nil
    end
    local optName = tokens[index]
    if optName==nil or optName:sub(1, 1)~="-" then
        return index, nil, nil
    end
    index = index + 1

    if optName=="--" then
        -- Treat following option like strings as arguments.
        return index, nil, nil
    end

    local matched, value
    for i, opt in ipairs(self._optionsConfig) do
        if opt.opts then
            if opt.opts[optName] then
                matched = opt
                local args
                args, index = self:_parseArguments(tokens, index, opt.nargs)
                if opt.nargs==1 then
                    value = args[1]
                else
                    value = args
                end
                if #args<opt.nargs then
                    context:appendError({
                                            type = OPT_ERROR_INADEQUATE_ARGS,
                                            opt = opt,
                                            optName = optName,
                                            args = args,
                                        })
                end
                break
            end
        else
            if opt.opts_on[optName] then
                matched, value = opt, true
                break
            end
            if opt.opts_off[optName] then
                matched, value = opt, false
                break
            end
        end
    end
    if matched==nil then
        context:appendError({
                                type = OPT_ERROR_INVALID_OPTION,
                                optName = optName,
                            })
        return index, nil, nil
    else
        local name = matched.name
        if matched.multiple then
            local valueArray = context.optionValues[name]
            if valueArray==nil or context._multipleOptionDefaults[valueArray] then
                context.optionValues[name] = { value, }
            else
                valueArray[#valueArray + 1] = value
            end
        else
            -- XXX If the value is already exists, overwrite it.
            context.optionValues[name] = value
        end
        return index, name, value
    end
end

function OptionsParser:_parseArguments(tokens, index, nargs)
    local values, ii = {}, 1
    while ii<=nargs do
        local tok = tokens[index]
        if tok==nil then break end
        index = index + 1
        values[ii], ii = tok, ii + 1
    end
    return values, index
end

--- @param context table @ The context returned by `startParsing()`.
--- @param tokens string[] @ Array of argument tokens.
--- @param index integer @ Index of next argument token.
--- @return integer @ Next token index.
function OptionsParser:parseArguments(context, tokens, index)
    if context.finished then
        return index
    end
    local arguments = context.arguments
    for i, arg in ipairs(self._argsConfig) do
        local nargs, values = arg.nargs, nil
        if nargs<0 then
            nargs = #tokens - index - nargs
            if nargs<0 then nargs = 0 end
        end
        values, index = self:_parseArguments(tokens, index, nargs)
        if arg.nargs==1 then
            arguments[arg.name] = values[1]
        else
            arguments[arg.name] = values
        end
        if #values<nargs then
            context:appendError({
                                    type = OPT_ERROR_INADEQUATE_ARGS,
                                    arg = arg,
                                    args = values,
                                })
            break
        end
    end
    return index
end

function OptionsParser:errorToString(error)
    if not error then
        return nil
    end
    if error.type == OPT_ERROR_INVALID_OPTION then
        return string.format("No such option: \"%s\"", error.optName)
    elseif error.type == OPT_ERROR_MISSING_OPTION then
        local expected
        local opt = error.opt
        if opt.opts~=nil then
            expected = string.concat(opt.opts, "\" / \"")
        else
            local opts = {}
            for _, name in ipairs(opt.opts_on) do opts[#opts + 1] = name end
            for _, name in ipairs(opt.opts_on) do opts[#opts + 1] = name end
            expected = string.concat(opts, "\" / \"")
        end
        return string.format("Missing option: \"%s\"", expected)
    elseif error.type == OPT_ERROR_INADEQUATE_ARGS then
        if error.opt~=nil then
            local nargs = error.opt.nargs
            return string.format("\"%s\" option requires %d %s",
                                 error.optName,
                                 nargs,
                                 nargs>1 and "arguments" or "argument"
            )
        end
        if error.arg~=nil then
            local args = error.args
            if args==nil or #args==0 then
                return string.format("Missing argument \"%s\"", error.arg.name)
            else
                local nargs = error.arg.nargs
                return string.format("Argument \"%s\" requires %d %s",
                                     error.arg.name,
                                     nargs,
                                     nargs>1 and "arguments" or "argument"
                )
            end
        end
    end
    return string.format("Parsing option error: %s", error.type)
end


--------------------------------------------------------------------------------
--- command classes

local function isFailed(retCode)
    return retCode~=nil and retCode~=true and retCode~=0
end

--- @class clt.HelpConfig : clt.OptionConfig
--- @field disabled boolean @ [Optional] Whether disable the help option. Default value is false.


--- @class clt.BaseCommandConfig
--- @field desc string @ [Optional] Description of the command.
--- @field help_option clt.HelpConfig @ [Optional] The configuration for help option.
--- @field options clt.OptionConfigs @ [Optional] Configurations for all options.
--- @field arguments clt.ArgumentConfigs[] @ [Optional] Configurations for arguments.


--- @class clt.BaseCommand
local BaseCommand = class("BaseCommand")

--- @desc Constructor of BaseCommand.
--- @param cfg clt.BaseCommandConfig @ Configuration for the command.
function BaseCommand:initialize(cfg)
    BaseCommand.__super__.initialize(self)
    self._description = cfg and cfg.desc or string.format("<%s>", self.__class__.__name__)
    local optionsConfig = cfg and cfg.options or {}
    if optionsConfig.metavar==nil then
        optionsConfig.metavar = #optionsConfig > 0 and "[OPTIONS]" or ""
    end
    optionsConfig[#optionsConfig + 1] = self:_makeHelpOption(cfg)
    local argsConfig = cfg and cfg.arguments
    self._optionsParser = OptionsParser(optionsConfig, argsConfig)
    self._ignoreExtraArguments = false
end

function BaseCommand:_makeHelpOption(cfg)
    local helpOption = cfg and cfg.help_option or { "--help", }
    if not helpOption.disabled then
        helpOption.name = "$HELP"
        helpOption.is_flag = true
        if helpOption.help==nil then
            helpOption.help = "Show this message and exit."
        end
        return helpOption
    end
    return nil
end

function BaseCommand:printf(fmt, ...)
    return print(string.format(fmt, ...))
end

function BaseCommand:description()
    return self._description or ""
end

function BaseCommand:usagePattern(proc)
    local parts = { proc, }
    local metavar = self._optionsParser:getOptionsMetavar()
    if metavar~=nil and metavar~="" then parts[#parts + 1] = metavar end
    local metavar = self._optionsParser:getArgumentsMetavar()
    if metavar~=nil and metavar~="" then parts[#parts + 1] = metavar end
    return table.concat(parts, " ")
end

function BaseCommand:usage(proc, showDescription)
    self:printf("Usage: %s", self:usagePattern(proc))
    if showDescription then
        local desc = self:description()
        if desc~=nil and desc~="" then
            self:printf("\n%s%s", "  ", desc)
        end
    end
end

function BaseCommand:help(proc)
    self:usage(proc, true)
    local printFunc = function (msg) self:printf("%s", msg) end
    self._optionsParser:printOptionsDescription("\nOptions:", "  ", printFunc)
    self._optionsParser:printArgumentsDescription("\nArguments:", "  ", printFunc)
end

function BaseCommand:execute(proc, args)
end

function BaseCommand:getExtraArguments()
    return self._extraArgs
end

function BaseCommand:ignoreExtraArguments(enabled)
    self._ignoreExtraArguments = enabled
end

function BaseCommand:checkExtraArguments(proc)
    if self._ignoreExtraArguments then
        return true
    end
    local args = self._extraArgs
    if args==nil or #args==0 then
        return true
    end
    self:usage(proc)
    self:printf("\n[error] Got unexpected extra %s (%s)",
                #args>1 and "arguments" or "argument",
                table.concat(args, " "))
    return false
end

--- @return boolean, table, table
function BaseCommand:parseOptions(proc, args, execBuiltinActions)
    if args==nil then
        args = self._extraArgs
    end

    local builtinAction
    local allBuiltinActions
    if execBuiltinActions then
        allBuiltinActions = { "$HELP", }
    end

    local optionsParser = self._optionsParser
    local index, opt, value = 1, nil, nil
    local context = optionsParser:startParsing(args, index)
    local optionValues = context.optionValues
    while true do
        index, opt, value = optionsParser:parseNextOption(context, args, index)
        if opt==nil then break end
        if allBuiltinActions~=nil then
            for i, action in ipairs(allBuiltinActions) do
                if optionValues[action] then builtinAction = action; break end
            end
            if builtinAction~=nil then
                break
            end
        end
    end
    index = optionsParser:parseArguments(context, args, index)
    optionsParser:finishParsing(context)

    if index>1 then
        self._extraArgs = self:shiftArgs(index-1, args)
    else
        self._extraArgs = args
    end

    if builtinAction=="$HELP" then
        self:help(proc)
        return 0
    end

    if context.error~=nil then
        self:usage(proc)
        self:printf("\n[error] %s", optionsParser:errorToString(context.error))
        return -1, context.error
    end

    return nil, context.optionValues, context.arguments
end

function BaseCommand:shiftArgs(n, args)
    if args==nil then
        args = self._extraArgs
    end
    local newArgs
    if n>0 and args~=nil then
        newArgs = {}
        for i = 1, #args-n do
            newArgs[i] = args[n+i]
        end
    else
        newArgs = args
    end
    self._extraArgs = newArgs
    return newArgs
end

function BaseCommand:setContext(context)
    self._context = context
end

function BaseCommand:getContext(context)
    return self._context
end


--- @class clt.CommandGroup
local CommandGroup = class("CommandGroup", BaseCommand)

--- @class clt.CommandGroupConfig : clt.BaseCommandConfig
--- @field chain boolean @ [Optional] Whether it is allowed to invoke more than one
---             subcommand in one go.
--- @field entry_func function @ [Optional] The entry function of this command.
--- @field subcommand_metavar string @ [Optional] Used for changing the meta variable
---             in the help page.


--- @desc Constructor of CommandGroup.
--- @param cfg clt.CommandGroupConfig @ Configuration for the command.
function CommandGroup:initialize(cfg)
    CommandGroup.__super__.initialize(self, cfg)
    self._subCommands = {}
    self._entryFunction = cfg.entry_func
    self._chain = cfg and cfg.chain and true or false
    self._subCommandMetavar = cfg and cfg.subcommand_metavar
    if self._subCommandMetavar==nil then
        if self._chain then
            self._subCommandMetavar = "COMMAND1 [ARGS]... [COMMAND2 [ARGS]...]..."
        else
            self._subCommandMetavar = "COMMAND [ARGS]..."
        end
    end
end

function CommandGroup:usagePattern(proc)
    local usage = CommandGroup.__super__.usagePattern(self, proc)
    return usage .. " " .. self._subCommandMetavar
end

function CommandGroup:help(proc)
    CommandGroup.__super__.help(self, proc)
    self:printCommandsDescription("\nCommands:", "  ")
end

function CommandGroup:printCommandsDescription(title, indents)
    self:printf("%s", title)
    local subcommands, width = {}, 19
    for name, cmd in pairs(self._subCommands) do
        local len = name:len()
        if len >= width then width = 4*math.floor((len+3)/4) - 1 end
        subcommands[#subcommands + 1] = { name = name, cmd = cmd }
    end
    table.sort(subcommands, function (a, b)
        return a.name < b.name
    end)
    local fmt = "%s%-" .. width .. "s  %s"
    for i = 1, #subcommands do
        local info = subcommands[i]
        self:printf(fmt, indents, info.name, info.cmd:description())
    end
end

function CommandGroup:execute(proc, args)
    local retCode, options, arguments = self:parseOptions(proc, args, true)
    if retCode~=nil then
        return retCode
    end

    if self._entryFunction~=nil then
        retCode = self._entryFunction(self, options, arguments)
        if retCode~=nil then
            return retCode
        end
    end

    args = self:getExtraArguments()
    local cmdName = args and args[1]
    if cmdName==nil then
        if #options==0 and #arguments==0 then
            self:help(proc)
            return 0
        end
        self:usage(proc)
        self:printf("\n[error] Missing command.")
        return -1
    end

    if not self._chain then
        local cmd = self._subCommands[cmdName]
        if cmd==nil then
            self:usage(proc)
            self:printf("\n[error] No such command: \"%s\"", cmdName)
            return -1
        end
        cmd:setContext(self:getContext())
        cmd:ignoreExtraArguments(self._ignoreExtraArguments)
        local subProc = proc.." "..cmdName
        retCode = cmd:execute(subProc, self:shiftArgs(1, args))
        self._extraArgs = cmd:getExtraArguments()
        if isFailed(retCode) then
            return retCode
        end
    else
        while cmdName~=nil do
            local cmd = self._subCommands[cmdName]
            if cmd==nil then
                self:usage(proc)
                self:printf("\n[error] No such command: \"%s\"", cmdName)
                return -1
            end
            cmd:setContext(self:getContext())
            cmd:ignoreExtraArguments(true)
            local subProc = proc.." "..cmdName
            args = self:shiftArgs(1, args)
            retCode = cmd:execute(subProc, args)
            if isFailed(retCode) then
                return retCode
            end
            args = cmd:getExtraArguments()
            self._extraArgs = args
            cmdName = args and args[1]
        end
    end

    if not self:checkExtraArguments(proc) then
        return -1
    end
    return 0
end

function CommandGroup:addCommand(name, command)
    assert(command~=nil)
    self._subCommands[name] = command
end


--- @class clt.FunctionCommand
local FunctionCommand = class("FunctionCommand", BaseCommand)

--- @class clt.FunctionCommandConfig : clt.BaseCommandConfig
--- @field entry_func function @ The entry function of this command.


--- @desc Constructor of FunctionCommand.
--- @param cfg clt.FunctionCommandConfig @ Configuration for the command.
function FunctionCommand:initialize(cfg)
    FunctionCommand.__super__.initialize(self, cfg)
    assert(cfg~=nil, "`cfg` is required")
    self._entryFunction = cfg.entry_func
    assert(self._entryFunction~=nil, "Entry function CANNOT be empty.")
end

function FunctionCommand:execute(proc, args)
    local retCode, options, arguments = self:parseOptions(proc, args, true)
    if retCode~=nil then
        return retCode
    end
    if not self:checkExtraArguments(proc) then
        return -1
    end
    return self._entryFunction(self, options, arguments)
end


--- @class clt.ExecuteFileCommand
local ExecuteFileCommand = class("ExecuteFileCommand", BaseCommand)

--- @class clt.ExecuteFileCommandConfig : clt.BaseCommandConfig
--- @field entry_file string @ The path of the target file.


--- @desc Constructor of ExecuteFileCommand.
--- @param cfg clt.ExecuteFileCommandConfig @ Configuration for the command.
function ExecuteFileCommand:initialize(cfg)
    ExecuteFileCommand.__super__.initialize(self, cfg)
    assert(cfg~=nil, "`cfg` is required")
    local filename = cfg.entry_file
    self._fileName = filename
    self._description = cfg.desc or string.format("Execute file '%s'", filename)
end

function ExecuteFileCommand:loadFileWithEnv(filename, env)
    local luaVersion = _G._VERSION
    if luaVersion == "Lua 5.1" then
        local module, error = loadfile(self._fileName)
        if module~=nil then
            module = setfenv(module, env)
        end
        return module, error
    elseif luaVersion == "Lua 5.2" or luaVersion == "Lua 5.3"  then
        return loadfile(self._fileName, "bt", env)
    end
end

function ExecuteFileCommand:execute(proc, args)
    local retCode, options, arguments = self:parseOptions(proc, args, true)
    if retCode~=nil then
        return retCode
    end
    if not self:checkExtraArguments(proc) then
        return -1
    end
    local env = setmetatable({
                                 _COMMAND = self,
                                 _OPTIONS = options,
                                 _ARGUMENTS = arguments,
                             },
                             {__index = _G})
    local module, error = self:loadFileWithEnv(self._fileName, env)
    if module~=nil then
        local extraArgs = self:getExtraArguments()
        return module(proc, unpack(args, 1, #args-#extraArgs))
    else
        self:printf("Failed to load file:\n%s", error)
        return -1
    end
end


--------------------------------------------------------------------------------
--- util functions

--- @desc Get the current module name.
local function __name__()
    if debug.getinfo(4, "n")==nil then
        return "__main__" -- main chunk
    else
        --local n, v = debug.getlocal(3, 1)
        --if n=="(*temporary)" then return v end
        local info = debug.getinfo(2, "nS")
        if info.what=="main" then
            local name = info.short_src
            name = name:gsub("^%./", "")
                       :gsub("%.[a-zA-Z0-9_-]+$", "")
                       :gsub("/", ".")
            return "[chunk] " .. name
        elseif info.what=="Lua" then
            return "[function] " .. (info.name or "(*anonymous)")
        else
            return info.what -- "[C]"
        end
    end
end

local function procName()
    return debug.getinfo(3, "S").short_src
end

--- @desc Execute the command.
--- @param command clt.BaseCommand @ The command object to be executed.
--- @param proc string @ The name of the procedure.
--- @param args string[] @ The arguments array.
local function exec(command, proc, args)
    local context = {}
    command:setContext(context)
    command:ignoreExtraArguments(false)
    return command:execute(proc~="" and proc or procName(), args)
end

--- @desc Execute the command and exit the program.
--- @param command clt.BaseCommand @ The command object to be executed.
--- @param proc string @ The name of the procedure.
--- @param args string[] @ The arguments array.
local function main(command, proc, args)
    local retCode = exec(command, proc~="" and proc or procName(), args)
    if not isFailed(retCode) then
        retCode = 0
    elseif type(retCode)~="number" then
        retCode = -1
    end
    return os.exit(retCode)
end

--------------------------------------------------------------------------------
-- export classes and functions

_M["_VERSION"] = "clt 0.1"

_M["OptionsParser"] = OptionsParser
_M["BaseCommand"] = BaseCommand
_M["CommandGroup"] = CommandGroup
_M["FunctionCommand"] = FunctionCommand
_M["ExecuteFileCommand"] = ExecuteFileCommand

_M["__name__"] = __name__
_M["exec"] = exec
_M["main"] = main

return _M
