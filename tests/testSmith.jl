using PyCall, DataFrames, CSV

libsbml = pyimport("libsbml")
reader = libsbml.SBMLReader()

pathXML = "/home/damiano/Distrobox/Debian/Master-thesis/Intermediate/PeTab_models/Smith_BMCSystBiol2013/model_Smith_BMCSystBiol2013.xml"
document = reader[:readSBML](pathXML)
model = document[:getModel]() # Get the model

modelDict = Dict()
modelDict["boolVariables"] = Dict()
modelDict["modelRuleFunctions"] = Dict()
modelDict["inputFunctions"] = Dict()
modelDict["parameters"] = Dict()
modelDict["states"] = Dict()


# Rewrites triggers in events to propper form for ModelingToolkit
function asTrigger(triggerFormula; returnParts=false)
    if "geq" == triggerFormula[1:3]
        strippedFormula = triggerFormula[5:end-1]
    elseif "gt" == triggerFormula[1:2]
        strippedFormula = triggerFormula[4:end-1]
    elseif "leq" == triggerFormula[1:3]
        strippedFormula = triggerFormula[5:end-1]
    elseif "lt" == triggerFormula[1:2]
        strippedFormula = triggerFormula[4:end-1]
    end
    parts = splitBetween(strippedFormula, ',')
    if occursin("time", parts[1])
        parts[1] = replaceWholeWord(parts[1], "time", "t")
    end
    expression = "[" * parts[1] * " ~ " * parts[2] * "]"
    if returnParts==true
        return expression, parts[1], parts[2]
    else
        return expression
    end
end


# Splits strings by a given delimiter, but only if the delimiter is not inside a function / parenthesis.
function splitBetween(stringToSplit, delimiter)
    parts = Vector{SubString{String}}(undef, length(stringToSplit))
    numParts = 0
    inParenthesis = 0
    startPart = 1
    endPart = 1
    for i in eachindex(stringToSplit)
        if stringToSplit[i] == '('
            inParenthesis += 1
        elseif stringToSplit[i] == ')'
            inParenthesis -= 1
        end
        if stringToSplit[i] == delimiter && inParenthesis == 0
            endPart = i-1
            numParts += 1
            parts[numParts] = stringToSplit[startPart:endPart]
            parts[numParts] = strip(parts[numParts])
            startPart = i+1
        end
    end
    numParts += 1
    parts[numParts] = stringToSplit[startPart:end]
    parts[numParts] = strip(parts[numParts])
    parts = parts[1:numParts]   
end

# Extracts the argument from a function.
# If a dictionary (with functions) is supplied, will also check if there are nested functions and will 
# include the arguments of these nested functions as arguments of the first function.
# The returned string will only contain unique arguments.
function getArguments(functionAsString, baseFunctions::Array{String, 1})
    parts = split(functionAsString, ['(', ')', '/', '+', '-', '*', ' ', '~', '>', '<', '=', ','], keepempty = false)
    arguments = Dict()
    for part in parts
        if isdigit(part[1])
            nothing
        else
            if (part in values(arguments)) == false && !(part in baseFunctions)
                arguments[length(arguments)+1] = part
            end
        end
    end
    if length(arguments) > 0
        argumentString = arguments[1]
        for i = 2:length(arguments)
            argumentString = argumentString * ", " * arguments[i]
        end
    else
        argumentString = ""
    end
    return argumentString
end
function getArguments(functionAsString, dictionary::Dict, baseFunctions::Vector{String})
    parts = split(functionAsString, ['(', ')', '/', '+', '-', '*', ' ', '~', '>', '<', '=', ','], keepempty = false)
    existingFunctions = keys(dictionary)
    includesFunction = false
    arguments = Dict()
    for part in parts
        if isdigit(part[1])
            nothing
        else
            if part in existingFunctions
                includesFunction = true
                funcArgs = dictionary[part][1]
                funcArgs = split(funcArgs, [',', ' '], keepempty = false)
                for arg in funcArgs
                    if (arg in values(arguments)) == false
                        arguments[length(arguments)+1] = arg
                    end
                end
            else
                if (part in values(arguments)) == false && !(part in baseFunctions)
                    arguments[length(arguments)+1] = part
                end
            end
        end
    end
    if length(arguments) > 0
        argumentString = arguments[1]
        for i = 2:length(arguments)
            argumentString = argumentString * ", " * arguments[i]
        end
    else
        argumentString = ""
    end
    return [argumentString, includesFunction]
end

# Replaces a word, "replaceFrom" in functions with another word, "replaceTo". 
# Often used to change "time" to "t"
# Makes sure not to change for example "time1" or "shift_time"
function replaceWholeWord(oldString, replaceFrom, replaceTo)
    
    replaceFromRegex = Regex("(\\b" * replaceFrom * "\\b)")
    newString = replace(oldString, replaceFromRegex => replaceTo)
    return newString

end



# Replaces words in oldString given a dictionary replaceDict.
# In the Dict, the key  is the word to replace and the second
# value is the value to replace with.
# Makes sure to only change whole words.
function replaceWholeWordDict(oldString, replaceDict)

    newString = oldString
    regexReplaceDict = Dict()
    for (key,value) in replaceDict
        replaceFromRegex = Regex("(\\b" * key * "\\b)")
        regexReplaceDict[replaceFromRegex] = "(" * value[2] * ")"
    end
    newString = replace(newString, regexReplaceDict...)

    return newString

end


# Substitutes the function with the formula given by the model, but replaces
# the names of the variables in the formula with the input variable names.
# e.g. If fun(a) = a^2 then "constant * fun(b)" will be rewritten as 
# "constant * b^2"
# Main goal, insert model formulas when producing the model equations.
# Example "fun1(fun2(a,b),fun3(c,d))" and Dict 
# test["fun1"] = ["a,b","a^b"]
# test["fun2"] = ["a,b","a*b"]
# test["fun3"] = ["a,b","a+b"]
# Gives ((a*b)^(c+d))
function replaceFunctionWithFormula(functionAsString, funcNameArgFormula)

    newFunctionsAsString = functionAsString
    
    for (key,value) in funcNameArgFormula
        # Find commas not surrounded by parentheses.
        # Used to split function arguments
        # If input argument are "pow(a,b),c" the list becomes ["pow(a,b)","c"]
        findOutsideCommaRegex = Regex(",(?![^()]*\\))")
        # Finds the old input arguments, removes spaces and puts them in a list
        replaceFrom = split(replace(value[1]," "=>""),findOutsideCommaRegex)

        # Finds all functions on the form "funName("
        numberOfFuns = Regex("\\b" * key * "\\(")
        # Finds the offset after the parenthesis in "funName("
        funStartRegex = Regex("\\b" * key * "\\(\\K")
        # Matches parentheses pairs to grab the arguments of the "funName(" function
        matchParenthesesRegex = Regex("\\((?:[^)(]*(?R)?)*+\\)")
        while !isnothing(match(numberOfFuns, newFunctionsAsString))
            # The string we wish to insert when the correct 
            # replacement has been made.
            # Must be resetted after each pass.
            replaceStr = value[2]
            # Extracts the function arguments
            funStart = match(funStartRegex, newFunctionsAsString)
            funStartPos = funStart.offset
            insideOfFun = match(matchParenthesesRegex, newFunctionsAsString[funStartPos-1:end]).match
            insideOfFun = insideOfFun[2:end-1]
            replaceTo = split(replace(insideOfFun,", "=>","),findOutsideCommaRegex)
            
            # Replace each variable used in the formula with the 
            # variable name used as input for the function.
            replaceDict = Dict()
            for ind in eachindex(replaceTo)
                replaceFromRegex = Regex("(\\b" * replaceFrom[ind] * "\\b)")
                replaceDict[replaceFromRegex] = replaceTo[ind]
            end
            replaceStr = replace(replaceStr, replaceDict...)

            if key != "pow"
                # Replace function(input) with formula where each variable in formula has the correct name.
                newFunctionsAsString = replace(newFunctionsAsString, key * "(" * insideOfFun * ")" => "(" * replaceStr * ")")
            else 
                # Same as above, but skips extra parentheses around the entire power.
                newFunctionsAsString = replace(newFunctionsAsString, key * "(" * insideOfFun * ")" => replaceStr)
            end

        end
    end
    return newFunctionsAsString
end

# Rewrites pow(base,exponent) into (base)^(exponent), which Julia can handle
function removePowFunctions(oldStr)

    powDict = Dict()
    powDict["pow"] = ["base, exponent","(base)^(exponent)"]
    newStr = replaceFunctionWithFormula(oldStr, powDict)
    return newStr

end


# For a SBML function extract the function arguments 
function getSBMLFuncArg(mathSBML)::String
    args = "("
    if mathSBML[:getNumChildren]() > 1
        args = args * mathSBML[:getLeftChild]()[:getName]()
        for n in range(1, mathSBML[:getNumChildren]()-1, step = 1)
            arg = mathSBML[:getChild](n)[:getName]()
            if arg !== nothing
                args = args * ", " * arg
            end
        end
        args = args * ")"
    end

    return args
end


function getSBMLFuncFormula(mathSBML, libsbml)

    mathAsString = libsbml[:formulaToString](mathSBML)
        
    # Remove any lambda and only keep the arguments and actual function formulation 
    expressionStart = findfirst('(', mathAsString)+1
    expressionStop = findlast(')', mathAsString)-1
    StrippedMathAsString = mathAsString[expressionStart:expressionStop]
        
    # Step through each comma and look backwards. 
    # If the only match is a single word it is an input parameter for lambda
    # if not it is the function formula.
    # The formula offset is initialized as the position of the final comma 
    # so that if the formula actually is just a single word, it will still be found.
    mtcOffset = findlast(',', StrippedMathAsString)+1

    splitByComma = Regex("[^,]+")
    isSingleWord = Regex("^\\s*\\b\\w+\\b\\s*\$")
    for mtc in eachmatch(splitByComma, StrippedMathAsString)
        if !occursin(isSingleWord, mtc.match)
            mtcOffset = mtc.offset
            break
        end
    end
    functionFormula = StrippedMathAsString[mtcOffset:end]
    functionFormula = removePowFunctions(functionFormula)

    return functionFormula
end

function test(model)
stringOfEvents = ""
for (eIndex, event) in enumerate(model[:getListOfEvents]())

    println("Model has an event :o :o")

    eventName = event[:getName]()
    trigger = event[:getTrigger]()
    triggerMath = trigger[:getMath]()
    triggerFormula = asTrigger(libsbml[:formulaToString](triggerMath))
    triggerFormula, p1, p2 = asTrigger(libsbml[:formulaToString](triggerMath),returnParts=true)
    eventAsString = ""
    for (eaIndex, eventAssignment) in enumerate(event[:getListOfEventAssignments]())
        variableName = eventAssignment[:getVariable]()
        # if the variable in the event is not set as a variable, make it so and remove it as a parameter or constant
        if variableName in keys(modelDict["parameters"])
            modelDict["nonConstantParameters"][variableName] = modelDict["parameters"][variableName]
            delete!(modelDict["parameters"], variableName)
        end

        eventMath = eventAssignment[:getMath]()
        eventMathAsString = libsbml[:formulaToString](eventMath)

        # Add the event 
        println("if(" * p1 * " == " * p2 * ", " * eventMathAsString * ", " * variableName * ")")
        if eaIndex == 1
            eventAsString = "[" * variableName * " ~ " * eventMathAsString
        else
            eventAsString = eventAsString * ", " * variableName * " ~ " * eventMathAsString
        end
    end
    eventAsString = eventAsString * "]"
    fullEvent = triggerFormula * " => " * eventAsString
    if eIndex == 1
        stringOfEvents = fullEvent
    else
        stringOfEvents = stringOfEvents * ", " * fullEvent
    end
end
println(stringOfEvents)
end

test(model)