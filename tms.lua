--[[
Credits to: SPEED, Grimes, SNAFU, CiriBob, Stonehouse, Lukrop and AJAX
they all inspired me to design this script....

tms.version = 0.96 BETA
major = 10
minor = 05
]]

--tms_blueTasks = 12				-- amount of designed tasks, also useable via doscript
--tms_redTasks = 7
tms_refresh = 5					-- 0=off, time of repeating the taskmessage
tms_answerTime = 10  			-- advised not to be lower than '5'!
tms_soundSystem = true  		-- if true you will get some cool voiceovers :)
tms_awacsRespawn = 300
tms_tankerRespawn = 300
tms_gcicapRespawn = 120
tms_taskCleanUp = 180
tms_sideTbl = {'blue','red'}
tms_roleTbl = {'cas','cap','sead','cargo'}
tms_blueHQ = 'Darkstar'
tms_redHQ = '000'
tms_bluecombatzone = 'bluecombatzone'
tms_redcombatzone = 'redcombatzone'

local tms_debug = true			-- selfdeclaring, I guess?
local tms_debug_ingame = false	-- with this set true you will also get realtime DEBUG Message in game

----------------------------------------------------------
-------------- never ever change this! -------------------
--- with this we are building the main data structure ----

task = {}
tms = {}
tms = {blue = tms_blueTasks, red = tms_redTasks}
deadGroup = {}
sideTbl = tms_sideTbl
roleTbl = tms_roleTbl
playerDetails = {}	-- Table <- all neccessary Data for each initialized unit will be stored there
unitIsDead = {}
schedule_updateUnits = nil

for a, side in pairs(sideTbl) do
	task[side] = {}
	deadGroup[side] = {}
	task[side].globalTaskPointer = 0
	task[side].randomNumTable = {}
	for b, role in pairs(roleTbl) do
		task[side][role] = {}
		task[side][role].activeTaskTable={}
		task[side][role].checkedInAndInZone=0
		task[side][role].parallelTasksAllowed=0
		task[side][role].roleTaskPointer=0
		deadGroup[side][role] = {}
		for taskNr=1, tms[side] do
			task[side][role][taskNr] = {groups={},zones={},mark=true,markerSchedule=nil,target=0,allied=0,start=nil,finish=nil,success=nil,description=nil}
			deadGroup[side][role][taskNr] = {target=0, allied=0}
		end
	end
end

task['blue'].hq = tms_blueHQ
task['red'].hq = tms_redHQ
task['blue'].zone = tms_bluecombatzone
task['red'].zone = tms_redcombatzone


------ is need to decide units are metric or not ----------
if not imperialUnits then
	imperialUnits = {}
	imperialUnits["Ka-50"] 			= false
	imperialUnits["Mi-8MT"] 		= false
	imperialUnits["UH-1H"] 			= true
	imperialUnits["Su-25"] 			= false
	imperialUnits["Su-25T"] 		= false
	imperialUnits["A-10A"] 			= true
	imperialUnits["A-10C"] 			= true
	imperialUnits["MiG-21Bis"] 		= false
	imperialUnits["Hawk"] 			= true
	imperialUnits["C-101EB"] 		= true
	imperialUnits["F-15C"] 			= true
	imperialUnits["Su-27"] 			= false
	imperialUnits["M-2000C"] 		= true
end
--------------------------------------------------------

function tms.debug(text)
	if not tms_debug then return end
	local debugText = '[TMS]' .. text
	env.info(debugText)
	if tms_debug_ingame then
		local msg = {}
		msg.msgFor = {coa = {'all'}}
		msg.displayTime = 5
		msg.text = debugText
		mist.message.add(msg)
	end
end

tms.debug('Initial tables have been build')

--@ just to make a string out of an enum
function tms.coaToSide(coa)
    if coa == coalition.side.NEUTRAL then return "neutral"
    elseif coa == coalition.side.RED then return "red"
    elseif coa == coalition.side.BLUE then return "blue"
    end
end

function tms.sideToCoa(side)
	if side == 'blue' then return coalition.side.BLUE
	elseif side == 'red' then return coalition.side.RED
	elseif side == 'neutral' then return coalition.side.NEUTRAL
	end
end

--@ used to know what kind of role an AC is designed for
function tms.taskType(groupName)
	if string.match(groupName, 'CAS') then return 'cas'
	elseif string.match(groupName, 'CAP') then return 'cap'
	elseif string.match(groupName, 'SEAD') then return 'sead'
	elseif string.match(groupName, 'CARGO') then return 'cargo'
	else
		env.info('No Role-Type found in group name: ' .. groupName)
	end
end

function tms.casualties(side)
	local ownGroundUnits=0
	local ownAirUnits=0
	local hostileGroundUnits=0
	local hostileAirUnits=0
	local casualtiesTbl = {}
	local all = 0
	if side == 'blue' then
		hostile = 'red'
	elseif side == 'red' then
		hostile = 'blue'	
	end
	for unitID, deadUnit in pairs(mist.DBs.deadObjects) do
	  all = all +1 
	  if deadUnit.objectData.coalition == side then
		if deadUnit.objectData.category == 'vehicle' then
		  ownGroundUnits=ownGroundUnits+1
		elseif deadUnit.objectData.category == 'plane' or deadUnit.objectData.category == 'helicopter' then
		  ownAirUnits=ownAirUnits+1
		end
	  elseif deadUnit.objectData.coalition == hostile then
		if deadUnit.objectData.category == 'vehicle' then
		  hostileGroundUnits=hostileGroundUnits+1
		elseif deadUnit.objectData.category == 'plane' or deadUnit.objectData.category == 'helicopter' then
		  hostileAirUnits=hostileAirUnits+1
		end
	  end
	end
	casualtiesTbl[#casualtiesTbl+1] = hostileAirUnits
	casualtiesTbl[#casualtiesTbl+1] = hostileGroundUnits
	casualtiesTbl[#casualtiesTbl+1] = ownAirUnits
	casualtiesTbl[#casualtiesTbl+1] = ownGroundUnits
	casualtiesTbl[#casualtiesTbl+1] = all
	return casualtiesTbl
end

function tms.buildPicture(unitName)
	local side = playerDetails[unitName].side
	local taskPointer = task[side].globalTaskPointer
	local picture = {}
	local taskSuccess = 0
	local taskFail = 0
	local buddys = 0
	local casualties = tms.casualties(side)
	picture[#picture + 1] = 'SITREP:\n'
	for i, role in pairs(roleTbl) do
		for index=1, taskPointer do
        	local taskNr = task[side].randomNumTable[index]
			if task[side][role][taskNr].success == true then taskSuccess = taskSuccess + 1
			elseif task[side][role][taskNr].success == false then taskFail = taskFail + 1 end
			buddys = buddys + task[side][role].checkedInAndInZone
		end
	end
	picture[#picture + 1] = 'Allied A/C on station: ' .. buddys .. '\n'
	picture[#picture + 1] = 'Orders achived:        ' .. taskSuccess .. '\n'
	picture[#picture + 1] = 'Orders failed:         ' .. taskFail .. '\n\n'
	--if casualties[1] ~= 0 and casualties[2] ~= 0 and casualties[3] ~= 0 and casualties[4] ~= 0 then
		picture[#picture + 1] = 'CASUALTIES in total: ' .. casualties[5] .. '\n'
		picture[#picture + 1] = 'HOSTILE Air Units:   ' .. casualties[1] .. ' Ground Units: ' .. casualties[2] .. '\n'
		picture[#picture + 1] = 'ALLIED   Air Units:   ' .. casualties[3] .. ' Ground Units: ' .. casualties[4] .. '\n'
	--end
	return table.concat(picture)
end

--@ this subsystem is an essential part of the script
--@ establish the voiceovers and all provieded messages
function tms.message(unit, command)
	local side = playerDetails[unit].side
	local role = playerDetails[unit].role
	local multsound = {}
	local msg = {}
	msg.msgFor = {units = {unit}}
	msg.displayTime = 5
	
	if tms_soundSystem then		
		if string.len(unit) < 4 then
			local callsignNumberFirst = string.sub(unit, 1, -3)
			local callsignNumberSecond = string.sub(unit, 2, -2)
			local callsignNumberLast = string.sub(unit, 3, -1)
			multsound[#multsound+1] = {time=0, 		file = '0-begin.ogg'}
			multsound[#multsound+1] = {time=0.4, 	file = '0-continue.ogg'}
			multsound[#multsound+1] = {time=0.8, 	file = '0-end.ogg'}
			multsound[#multsound+1] = {time=1.2, 	file = 'message_this_is.ogg'}
			multsound[#multsound+1] = {time=1.6, 	file = callsignNumberFirst ..'-begin.ogg'}
			multsound[#multsound+1] = {time=2, 		file = callsignNumberSecond ..'-continue.ogg'}
			multsound[#multsound+1] = {time=2.4, 	file = callsignNumberLast .. '-end.ogg'}
		else
			local callsignName = string.sub(unit, 0, -3)
			local callsignNumber = string.sub(unit, -2)
			local callsignNumberLast = string.sub(callsignNumber, -1)
			local callsignNumberFirst = string.sub(callsignNumber, 0, 1)
			multsound[#multsound+1] = {time=0, 		file = 'callsign_' .. task[side].hq .. '.ogg' }
			multsound[#multsound+1] = {time=1, 		file = 'message_this_is.ogg'}
			multsound[#multsound+1] = {time=1.5, 	file = 'callsign_' .. callsignName ..'.ogg'}
			multsound[#multsound+1] = {time=2, 		file = callsignNumberFirst .. '-begin.ogg'}
			multsound[#multsound+1] = {time=2.3, 	file = callsignNumberLast .. '-end.ogg'}
		end
	end

	if command == 'checkin' then	
		--question
		msg.text = task[side].hq .. ', this is ' .. unit .. ', available for tasking!'
		if tms_soundSystem then
			multsound[#multsound+1] = {time=3.0, 	file = 'message_Available for tasking.ogg'}
			msg.multSound = multsound
		end
		mist.message.add(msg)
		---answer
		msg.multSound = nil
		msg.text = unit .. ', this is ' .. task[side].hq  .. '. Roger!'
		mist.scheduleFunction(mist.message.add, {msg}, timer.getTime() + tms_answerTime)
	elseif command == 'checkout' then
		--question
		msg.text = task[side].hq  .. ', this is ' .. unit .. ', checking Out!'
		if tms_soundSystem then
			multsound[#multsound+1] = {time=3.0, 	file = 'message_checking_out.ogg'}
			msg.multSound = multsound
		end
		mist.message.add(msg)
		---answer
		msg.multSound = nil
		msg.text = unit .. ', this is ' .. task[side].hq .. '. Roger!'
		mist.scheduleFunction(mist.message.add, {msg}, timer.getTime() + tms_answerTime)
	elseif command == 'picture' then
		--question
		msg.text = task[side].hq .. ', this is ' .. unit .. ', request picture?'
		if tms_soundSystem then	
			multsound[#multsound+1] = {time=3.0,	file = 'message_request_picture.ogg'}
			msg.multSound = multsound
		end
		mist.message.add(msg)
		---answer
		msg.displayTime = 10
		msg.multSound = nil
		msg.text = tms.buildPicture(unit)
		mist.scheduleFunction(mist.message.add, {msg}, timer.getTime() + tms_answerTime)
	elseif command == 'trigger' then
		msg.text = task[side].hq .. ', this is ' .. unit .. ', request tasking!'
		if tms_soundSystem then
			multsound[#multsound+1] = {time=3.0, 	file = 'message_request_tasking.ogg'}
			msg.multSound = multsound
		end
		mist.message.add(msg)
		msg.multSound = nil
		msg.text = unit .. ', this is ' .. task[side].hq .. ', standby!'
		mist.scheduleFunction(mist.message.add, {msg}, timer.getTime() + tms_answerTime)
	elseif command == 'notinzone' then
		--question
		msg.text = task[side].hq .. ', this is ' .. unit .. ', available for tasking!'
		if tms_soundSystem then
			multsound[#multsound+1] = {time=3.0, 	file = 'message_Available for tasking.ogg'}
			msg.multSound = multsound
		end
		mist.message.add(msg)
		---answer
		msg.multSound = nil
		msg.text = unit .. ', this is ' .. task[side].hq  .. ', first you have to go on IP!'
		mist.scheduleFunction(mist.message.add, {msg}, timer.getTime()+tms_answerTime)
	elseif command == 'smoke_on' then
		--question
		msg.text = task[side].hq .. ', this is ' .. unit .. ', request WP!'
		-- if tms_soundSystem then
			-- multsound[#multsound+1] = {time=3.0, 	file = 'message_Available for tasking.ogg'}
			-- msg.multSound = multsound
		-- end
		mist.message.add(msg)
		---answer
		msg.multSound = nil
		msg.text = unit .. ', this is ' .. task[side].hq  .. ', mark is on the deck!'
		mist.scheduleFunction(mist.message.add, {msg}, timer.getTime()+6)
	end
end

function tms.smokeMarker(groups)
	trigger.action.smoke(mist.getAvgPos(mist.makeUnitTable(groups)), trigger.smokeColor.White)
	tms.debug('SMOKEMARKER ON!')
end

function tms.markTarget(vars)
	local side = playerDetails[vars[1]].side
	local role = playerDetails[vars[1]].role
	local taskNr = playerDetails[vars[1]].taskNr
	local taskGroups = {}
	if vars[2] == 0 then
		task[side][role][taskNr].mark = false
		mist.removeFunction(task[side][role][taskNr].markerSchedule)
		task[side][role][taskNr].markerSchedule = nil
		tms.debug('MARKER OFF')
	elseif vars[2] == 1 then
		task[side][role][taskNr].mark = true
		for i=1, #task[side][role][taskNr].groups do
			if string.match(task[side][role][taskNr].groups[i], 'target') then
				local temp = '[g]' .. task[side][role][taskNr].groups[i]
				table.insert(taskGroups, temp)
			end
		end
		tms.message(vars[1], 'smoke_on')
		task[side][role][taskNr].markerSchedule = mist.scheduleFunction(tms.smokeMarker, {taskGroups}, timer.getTime(), 210)
		tms.debug('MARKER ON')
	end
end

function tms.makeTaskMsgText(unit, taskNr)
	local side = playerDetails[unit].side
	local role = playerDetails[unit].role
	local groupTable = task[side][role][taskNr].groups
	local somethingSpecial = false
	local text = {}
	local output = nil
	local header = 'Order# ' .. task[side][role].roleTaskPointer .. '\n\n'
	local units = {}
	
	if role == 'cas' or role == 'cargo' then
		for index=1, #groupTable do
			if string.match(groupTable[index], 'bomb') then
				if string.match(groupTable[index], 'bridge') then 	
					text[#text + 1] = 'Destroy bridge at '
					somethingSpecial = true
				elseif string.match(groupTable[index], 'comm') then
					text[#text + 1] = 'Destroy hostile Comand-Center at '
					somethingSpecial = true
				elseif string.match(groupTable[index], 'bunker') then
					text[#text + 1] = 'Destroy hostile Bunker at '
					somethingSpecial = true
				elseif string.match(groupTable[index], 'depot') then
					text[#text + 1] = 'Destroy hostile Warehouse at '
					somethingSpecial = true
				elseif string.match(groupTable[index], 'complex') then
					text[#text + 1] = 'Destroy industrial Complex at '
					somethingSpecial = true
				end
			end
		end
	end
	if somethingSpecial ~= true then
		for j=1, #task[side][role][taskNr].groups do
			if string.match(task[side][role][taskNr].groups[j], 'target') then
				local unitsInGroup = Group.getByName(task[side][role][taskNr].groups[j]):getUnits()
				for k=1, #unitsInGroup do
					local unitTypeName = unitsInGroup[k]:getTypeName()
					if not units[unitTypeName] then
						units[unitTypeName] = 1
					else
						units[unitTypeName] = units[unitTypeName] + 1
					end
				end
			end
		end
		text[#text + 1] = 'Your target(s):\n'
		for ofUnits, amount in pairs(units) do
			text[#text + 1] = amount .. 'x ' .. ofUnits .. '\n'			
		end
		text[#text + 1] = '\n'
	end
	if tmsDescr[side] then
		local temptext = tmsDescr[side][taskNr]
		output = header .. temptext .. '\n\n' .. table.concat(text)
	else
		output = header .. table.concat(text)
	end
	return output
end
	
function tms.taskmsg(unit, taskNr)
	local side = playerDetails[unit].side
	local role = playerDetails[unit].role
	local unitType = playerDetails[unit].unitType
	local taskUnits = {}
	for i=1, #task[side][role][taskNr].groups do
		if string.match(task[side][role][taskNr].groups[i], 'target') then
			local temp = '[g]' .. task[side][role][taskNr].groups[i]
			table.insert(taskUnits, temp)
		end
	end
	local text = tms.makeTaskMsgText(unit, taskNr)
	local msg = {}
	msg.msgFor = {units = {unit}}
	msg.displayTime = playerDetails[unit].interval - 1
	msg.acc = 3
	msg.units =	mist.makeUnitTable(taskUnits)
	if role == 'cap' then
        msg.ref = unit
		msg.text = text .. 'Fly: '
		if not imperialUnits[unitType] then 
            msg.metric = true
        else
            msg.metric = false
        end
        mist.msgBRA(msg)
    elseif role ~= 'cap' then
    	if unitType == 'A-10C' then
			msg.text = text	.. 'Coordinates: '	
			mist.msgMGRS(msg)
		elseif unitType == 'Ka-50' then
			msg.DMS = true
			msg.text = text	.. 'Coordinates: '	
			mist.msgLL(msg)
		else
			msg.text = text	.. '\nFly: '	
			msg.ref=Unit.getByName(unit):getPosition().p
			msg.metric = true
			mist.msgBR(msg)
		end
    end
end

function tms.messageRefresh(selection)
	local unit = selection[1]
	local interval = selection[2]
	if interval == 0 then
		mist.removeFunction(playerDetails[unit].scheduleID)
		playerDetails[unit].scheduleID = nil
		tms.debug('Messageloop for ' .. unit .. ' removed!')
	else
		playerDetails[unit].interval = interval
		return true
	end
end

function tms.loopTaskMessage(unit, taskNr)
	playerDetails[unit].taskNr = taskNr
	if playerDetails[unit].scheduleID == nil then
		playerDetails[unit].scheduleID = mist.scheduleFunction(tms.taskmsg, {unit, taskNr}, timer.getTime(), playerDetails[unit].interval)
		tms.debug('LOOPTASKMESSAGE: no existing schedule. Start Schedule for: ' .. unit .. ' with taskNr: ' .. taskNr)
	elseif playerDetails[unit].scheduleID ~= nil then
		tms.debug('LOOPTASKMESSAGE: Existing schedule removed: ' .. playerDetails[unit].scheduleID)
		mist.removeFunction(playerDetails[unit].scheduleID)
		playerDetails[unit].scheduleID = nil
		playerDetails[unit].scheduleID = mist.scheduleFunction(tms.taskmsg, {unit, taskNr}, timer.getTime(), playerDetails[unit].interval)
		tms.debug('LOOPTASKMESSAGE: NEW Schedule startet for: ' .. unit .. ' with taskNr: ' .. taskNr)
	end
end

function tms.picture(unit)
	local side = playerDetails[unit].side
	local role = playerDetails[unit].role
	tms.debug('PICTURE Task#: ' .. #task[side][role].activeTaskTable .. ' FOR UNIT: ' .. unit)
	tms.message(unit, 'picture')
	return
end

function tms.showtask(selection)
	local unit = selection[1]
	local command = selection[2]
	local side = playerDetails[unit].side
	local role = playerDetails[unit].role
	local taskFlag = #task[side][role].activeTaskTable
	if playerDetails[unit].checkedin == true then
		if command == 1 and taskFlag > 0 then			
			tms.loopTaskMessage(unit, task[side][role].activeTaskTable[1])
		elseif command == 2 and taskFlag > 1 then
			tms.loopTaskMessage(unit, task[side][role].activeTaskTable[2])
		elseif command == 3 and taskFlag > 2 then
			tms.loopTaskMessage(unit, task[side][role].activeTaskTable[3])
		end
	end
end

function tms.updatePlayersInZone() 
	for unit, v in pairs(playerDetails) do
	--local unit = next(playerDetails)
	--repeat
		if playerDetails[unit].active == true then
			local unitPos = Unit.getByName(unit):getPoint()      
			--local role = playerDetails[unit].role
			local side = playerDetails[unit].side
			local zonePoints = mist.getGroupPoints(task[side].zone)
			local isUnitInZone = mist.pointInPolygon(unitPos, zonePoints)
			local wasUnitInZone = playerDetails[unit].inZone
			if isUnitInZone and not wasUnitInZone then
				playerDetails[unit].inZone = true
				tms.debug('ZONE PLAYER IN: ' .. unit)
				return true
			elseif not isUnitInZone and wasUnitInZone then
				playerDetails[unit].inZone = false
				tms.messageRefresh({unit, 0})
				tms.checkout(unit)
				tms.debug('ZONE PLAYER LEFT: ' .. unit)
				return false
			end
		end
		--unit = next(playerDetails, unit)
	--until unit == nil
	end
end

function tms.checkin(unit)
	local side = playerDetails[unit].side
	local role = playerDetails[unit].role
	if not playerDetails[unit].checkedin and playerDetails[unit].inZone then									-- Pilot checks in for the first time
		playerDetails[unit].checkedin = true
		task[side][role].checkedInAndInZone = task[side][role].checkedInAndInZone + 1							-- increase the counter of units "checkedin & inZone"
			if task[side][role].checkedInAndInZone <=2 then task[side][role].parallelTasksAllowed = 1
			elseif task[side][role].checkedInAndInZone > 2 then task[side][role].parallelTasksAllowed = 2
			elseif task[side][role].checkedInAndInZone > 4 then task[side][role].parallelTasksAllowed = 3 end
		tms.message(unit, 'checkin')
		tms.triggerTask(unit) 																					-- time to give them some orders :-)
	elseif playerDetails[unit].checkedin and playerDetails[unit].inZone then									-- Pilot reasks for orders
		tms.message(unit, 'trigger')
		tms.triggerTask(unit)																					-- give him what he asked for..
	elseif not playerDetails[unit].inZone then
		tms.message(unit, 'notinzone')
	end
end

function tms.triggerTask(unit)
	local side = playerDetails[unit].side
	local role = playerDetails[unit].role
	if #task[side][role].activeTaskTable < task[side][role].parallelTasksAllowed then
		tms.debug('TRIGGER Side: '.. string.upper(side) .. ' Role: ' .. string.upper(role) .. ' #TaskTable: ' .. #task[side][role].activeTaskTable .. '. Allowed: ' .. task[side][role].parallelTasksAllowed)
		if task[side].globalTaskPointer < 1 or 
		task[side].globalTaskPointer == task[side][role].roleTaskPointer then
			tms.debug('TRIGGER Global: ' .. task[side].globalTaskPointer .. ' Local: ' .. task[side][role].roleTaskPointer .. ' start Task')
			task[side].globalTaskPointer = task[side].globalTaskPointer + 1				-- increse Global Counter
			task[side][role].roleTaskPointer = 	task[side].globalTaskPointer			-- set local counter to same value
			local taskNr = task[side].randomNumTable[task[side][role].roleTaskPointer]	-- pick the taskNr to be activating
			tms.startTask(unit, taskNr)
			tms.debug('TRIGGER TaskNr started: ' .. taskNr)
		elseif task[side].globalTaskPointer > task[side][role].roleTaskPointer then
			tms.debug('TRIGGER Global: ' .. task[side].globalTaskPointer .. ' Local: ' .. task[side][role].roleTaskPointer .. ' start Task')
			task[side][role].roleTaskPointer = task[side].globalTaskPointer
			local taskNr = task[side].randomNumTable[task[side][role].roleTaskPointer]	-- pick the taskNr to be activating
			tms.startTask(unit, taskNr)	
			tms.debug('TRIGGER TaskNr started: ' .. taskNr)
		elseif task[side].globalTaskPointer == #task[side].randomNumTable then
			tms.debug('TRIGGER NO MORE TASKS AVAILABLE!')
		else
			tms.debug('TRIGGER ActiveTaskTable: ' .. #task[side][role].activeTaskTable .. ' <  then allowed: ' .. task[side][role].parallelTasksAllowed)
		end
	elseif #task[side][role].activeTaskTable > 0 then
		tms.debug('TRIGGER One task available and displayed via Messageloop')
		mist.scheduleFunction(tms.loopTaskMessage, {unit, task[side][role].activeTaskTable[1]}, timer.getTime() + 15)
	end
end

--@ all neccessary data will be collected and stored and used to activat all relevant groups
function tms.startTask(unit, taskNr)
	local side = playerDetails[unit].side
	local role = playerDetails[unit].role
	-- activate all groups by fetched and stored data
	for i=1, #task[side][role][taskNr].groups do
		if not string.match(task[side][role][taskNr].groups[i], 'later') then
			Group.getByName(task[side][role][taskNr].groups[i]):activate()
		end
	end
	tms.debug('STARTTASK ActivateGroups...Target: ' .. task[side][role][taskNr].target .. ' Allied: ' .. task[side][role][taskNr].allied)
	task[side][role][taskNr].start = timer.getTime()
	table.insert(task[side][role].activeTaskTable, taskNr)
	local msg = {}
	msg.msgFor = {units = {unit}}
	msg.displayTime = 5
	msg.text = unit .. ', this is ' .. task[side].hq .. ', new ' .. string.upper(role) .. ' Order available!'
	mist.scheduleFunction(mist.message.add, {msg}, timer.getTime()+12)
	mist.scheduleFunction(tms.loopTaskMessage, {unit, taskNr}, timer.getTime() + 17)
end

--@ this will be called via F10 or if the schedule will see that a unit isnt in the combatzone any longer
function tms.checkout(unit)
	local side = playerDetails[unit].side
	local role = playerDetails[unit].role
	--tms.updatePlayersInZone()
	if playerDetails[unit].checkedin then
		playerDetails[unit].checkedin = false
		task[side][role].checkedInAndInZone = task[side][role].checkedInAndInZone - 1
		tms.message(unit, 'checkout')
	end
end

--@ this will init the F10 menu the first time a player jumps into a Cockpit
function tms.init(unit)
	if not playerDetails[unit].init then
		local gid = playerDetails[unit].gid
		-- providing the initial F10 items
		playerDetails[unit].menu[1] = missionCommands.addSubMenuForGroup(gid, 'Tasking'	  , nil)
		playerDetails[unit].menu[2] = missionCommands.addCommandForGroup(gid, 'Request Task' , playerDetails[unit].menu[1], tms.checkin,  unit)
		playerDetails[unit].menu[3] = missionCommands.addCommandForGroup(gid, 'Picture'	     , playerDetails[unit].menu[1], tms.picture,  unit)
		playerDetails[unit].menu[4] = missionCommands.addCommandForGroup(gid, 'Check Out'    , playerDetails[unit].menu[1], tms.checkout, unit)
		playerDetails[unit].menu[5] = missionCommands.addCommandForGroup(gid, 'Message Off'  , playerDetails[unit].menu[1], tms.messageRefresh, {unit,0})
		playerDetails[unit].menu[6] = missionCommands.addSubMenuForGroup(gid, 'Task Details' , playerDetails[unit].menu[1])
		playerDetails[unit].menu[7] = missionCommands.addCommandForGroup(gid, 'Task#1 info'  , playerDetails[unit].menu[6], tms.showtask, {unit, 1})
		playerDetails[unit].menu[8] = missionCommands.addCommandForGroup(gid, 'Task#2 info'  , playerDetails[unit].menu[6], tms.showtask, {unit, 2})
		playerDetails[unit].menu[9] = missionCommands.addCommandForGroup(gid, 'Task#3 info'  , playerDetails[unit].menu[6], tms.showtask, {unit, 3})
		if playerDetails[unit].role == 'cas' or playerDetails[unit].role == 'sead' then
			playerDetails[unit].menu[10]= missionCommands.addSubMenuForGroup(gid, 'Target Marker', playerDetails[unit].menu[1])
			playerDetails[unit].menu[11]= missionCommands.addCommandForGroup(gid, 'WP'   , playerDetails[unit].menu[10], tms.markTarget, {unit, 1})
			-- if playerDetails[unit].unitType == 'A-10C' or playerDetails[unit].unitType == 'Ka-50' then
				-- playerDetails[unit].menu[12]= missionCommands.addCommandForGroup(gid, 'Laser', playerDetails[unit].menu[10], tms.markTarget, {unit, 2})
				-- playerDetails[unit].menu[13]= missionCommands.addCommandForGroup(gid, 'IR'   , playerDetails[unit].menu[10], tms.markTarget, {unit, 3})
			-- end
			playerDetails[unit].menu[14]= missionCommands.addCommandForGroup(gid, 'OFF'  , playerDetails[unit].menu[10], tms.markTarget, {unit, 0})
		end
		playerDetails[unit].init = true
	end
end

--@ to build a string to display it in a MIL Style
function tms.buildTime(sec, mode)
	local dayTime = math.modf(sec, 86400)
	local hh = math.floor(dayTime / 3600)
	dayTime = dayTime - hh * 3600
	local mm = math.floor(dayTime / 60)
	if mode == 'mil' then
		return string.format('%02d', hh) .. string.format('%02d', mm) .. 'h'
	elseif mode == 'dur' then
		return string.format('%02d', hh) .. ':' .. string.format('%02d', mm)
	end
end

--@ anytime a task has finished this will give a little summary
function tms.taskFinishMessage(side, role, taskNr)
	local success = task[side][role][taskNr].success
	local duration = task[side][role][taskNr].finish - task[side][role][taskNr].start
	local orderNr = task[side][role].roleTaskPointer
	local msg = {}
	msg.msgFor = {coa = {side}}
	msg.displayTime = 15
	if success == true then
		text = '\nThis is ' .. task[side].hq .. ', ' .. string.upper(side) .. ' Order# ' .. orderNr .. ' objectives successfull!\n\nTime of duration(HH:MM): ' .. tms.buildTime(duration, 'dur')
	else
		text = '\nThis is ' .. task[side].hq .. ', ' .. string.upper(side) .. ' Order# ' .. orderNr .. ' has failed!\nTime of duration(HH:MM): ' .. tms.buildTime(duration, 'dur')
	end
	if #task[side][role].activeTaskTable == 0 then
		msg.text = text .. '\n\nThere are no further taskings for you!\n'
	else
		msg.text = text .. '\n\nThere are ' .. #task[side][role].activeTaskTable .. ' other active tasks at the moment!'
	end
	mist.message.add(msg)
end

--@ deactive all units no longer be neccessary
--@ this is for cleanup purpose
--@ DCS beginns to struggle if there are too much Ground units
function tms.deactivateGroups(groupTable)
	for i=1, #groupTable do
		if Group.getByName(groupTable[i]) then
			Group.getByName(groupTable[i]):destroy()
		end
	end
end

--@ the event system will call this if a task is over
function tms.taskOver(side, role, taskNr, success)
	for index=1, #task[side][role].activeTaskTable do
		if task[side][role].activeTaskTable[index] == taskNr then
			table.remove(task[side][role].activeTaskTable, index)
			tms.debug('TASK-OVER Task#: ' .. taskNr .. ' removed out of Tasktable')
		end
	end
	--local unit = next(playerDetails)
	--while unit ~= nil do
	for unit, k in pairs(playerDetails) do
		if playerDetails[unit].taskNr == taskNr then 
			tms.messageRefresh({unit, 0}) 
			playerDetails[unit].taskNr = 0
			tms.debug('TASK-OVER Looped message for ' .. unit .. ' canceled!')
		end
		--unit = next(playerDetails, unit)
	end
	task[side][role][taskNr].finish = timer.getTime()
	task[side][role][taskNr].success = success
	mist.removeFunction(task[side][role][taskNr].markerSchedule)
	task[side][role][taskNr].markerSchedule = nil
	tms.taskFinishMessage(side, role, taskNr)
	mist.scheduleFunction(tms.deactivateGroups, {task[side][role][taskNr].groups}, timer.getTime() + tms_taskCleanUp)
end

--@ check by EVENT if a whole group is dead and if it is allied or hostile
function tms.checkDeadGroup(unitName)
	local coa = mist.DBs.unitsByName[unitName].coalition
	local groupName = mist.DBs.unitsByName[unitName].groupName
	if Group.getByName(groupName) == nil then return end
	if string.match(groupName, 'awacs') then
		mist.scheduleFunction(mist.respawnGroup, {groupName, true}, timer.getTime() + tms_awacsRespawn)
		tms.debug('DEAD-GROUP: Side: ' .. coa .. ' AWACS dead. Respawn in ' .. tms_awacsRespawn .. ' seconds!' )
	elseif string.match(groupName, 'tanker') then
		mist.scheduleFunction(mist.respawnGroup, {groupName, true}, timer.getTime() + tms_tankerRespawn)
		tms.debug('DEAD-GROUP: Side: ' .. coa .. ' TANKER dead. Respawn in ' .. tms_tankerRespawn .. ' seconds!' )
	elseif string.match(groupName, 'gcicap') then
		mist.scheduleFunction(mist.cloneGroup, {groupName, true}, timer.getTime() + tms_gcicapRespawn)
		tms.debug('DEAD-GROUP: Side: ' .. coa .. ' GCICAP dead. Respawn in ' .. tms_gcicapRespawn .. ' seconds!' )
	else
		tms.debug('DeadUnit of ' .. groupName .. ' Unitname: ' .. unitName)
		for i, side in pairs(sideTbl) do
			for j, role in pairs(roleTbl) do
				for k=1, #task[side][role].activeTaskTable do
					local taskNr = task[side][role].activeTaskTable[k]
					for l=1, #task[side][role][taskNr].groups do
						if task[side][role][taskNr].groups[l] == groupName then
							if string.match(task[side][role][taskNr].groups[l],'target') then
								deadGroup[side][role][taskNr].target = deadGroup[side][role][taskNr].target + 1
								tms.debug('DEAD-GROUP: ' .. groupName .. ' dead target units: ' .. deadGroup[side][role][taskNr].target)
								if task[side][role][taskNr].target == deadGroup[side][role][taskNr].target then
									tms.taskOver(side, role, taskNr, true)
								end
							elseif string.match(task[side][role][taskNr].groups[l], 'allied') then
								deadGroup[side][role][taskNr].allied = deadGroup[side][role][taskNr].allied + 1
								tms.debug('DEAD-GROUP: ' .. groupName .. ' dead allied units: '  .. deadGroup[side][role][taskNr].allied)
								if task[side][role][taskNr].allied == deadGroup[side][role][taskNr].allied then
									tms.taskOver(side, role, taskNr, false)
								end
							end
						end
					end
				end
			end
		end
	end
end

--@ a Player has left his SLOT intentionaly or not but will be deletet
function tms.deletePlayer(unitName)
	local side = playerDetails[unitName].side
	local role = playerDetails[unitName].role
	if playerDetails[unitName].active and playerDetails[unitName].inZone and playerDetails[unitName].checkedin and task[side][role].checkedInAndInZone > 0 then
		task[side][role].checkedInAndInZone = task[side][role].checkedInAndInZone - 1
	end
	playerDetails[unitName].inZone = false
	playerDetails[unitName].checkedin = false
	playerDetails[unitName].active = false
	tms.messageRefresh({unitName, 0})
end

--@ fetch all Data about a player and store it within this array for later use
function tms.getPlayerDetails(unit)
	if not playerDetails[unit] then 
		playerDetails[unit] = {} 
	end
	local unitClass = Unit.getByName(unit)
    local side = tms.coaToSide(unitClass:getCoalition())
    local group = unitClass:getGroup()
    local groupName = group:getName()
    local gid = group:getID()
    local unitType = unitClass:getTypeName() 
	playerDetails[unit].side = side
	playerDetails[unit].group = groupName
	playerDetails[unit].gid = gid
	playerDetails[unit].unitType = unitType
	playerDetails[unit].interval = tms_refresh
	playerDetails[unit].scheduleID = nil
	playerDetails[unit].checkedin = false
	playerDetails[unit].role = tms.taskType(groupName)
	playerDetails[unit].active = true
	playerDetails[unit].menu = {}
	if playerDetails[unit].taskNr ~= 0 then  
		playerDetails[unit].taskNr = playerDetails[unit].taskNr
	else
		playerDetails[unit].taskNr = 0
	end
	return playerDetails[unit]
end

function tms.stopSchedule()
	if not schedule_updateUnits then 
		tms.debug('PLAYERDELETE: Schedule doesn´t exists!')
		return
	end
	local counter = 0
	for player, k in pairs(playerDetails) do
		if playerDetails[player].active == true then counter = counter +1 end
	end
	if counter < 1 then
		if schedule_updateUnits then
			tms.debug('PLAYERDELETE: check if Players in Zone removed')
			mist.removeFunction(schedule_updateUnits)
			schedule_updateUnits = nil
		else
			tms.debug('PLAYERDELETE: something went wrong to delete scheduled function!')
		end
	else
		tms.debug('PLAYERDELETE: scheduled not stopped while ' .. counter .. ' players still active!')
	end
end

--@ the heart of the script, nearly everything will be released by events or via F10 menu
function tms.eventHandler(event)
	local function ifHuman(unitName)
		for player, i in pairs(playerDetails) do
			if player == unitName then
				return true
			else
				return false
			end
		end
	end
	local function ifObject(unitName)
		if mist.DBs.deadObjects[tonumber(unitName)] and mist.DBs.deadObjects[tonumber(unitName)].objectType == 'building' then 
			return true
		else 
			return false 
		end
	end
	
	--@ a player jumps in an available slot
	if event.id == world.event.S_EVENT_PLAYER_ENTER_UNIT then 	
		local unitName = event.initiator:getName()
		-- Player jumps into unit for the first time
		if not playerDetails[unitName] then
			tms.debug('EVENT: First time player information will collected: ' .. unitName)
			tms.getPlayerDetails(unitName)
			tms.init(unitName)
		else
			playerDetails[unitName].active = true
		end
		-- if awacs script is already running
		if awacs and not awacs.awacsCommandsInstalled[unitName] then
			awacs.getAwacsUnits()
			awacs.installAwacsCommands(unitName)
		end
		if not schedule_updateUnits then 
			schedule_updateUnits = mist.scheduleFunction(tms.updatePlayersInZone, {nil}, timer.getTime()+1, 30)
			tms.debug('PLAYERDETAILS: Zone check schedule startet!')
		end
	
	--@ player left slot by exiting
	elseif event.id == world.event.S_EVENT_PLAYER_LEAVE_UNIT and event.initiator ~= nil then
		local unitName = event.initiator:getName()
		if playerDetails[unitName].active == true then
			tms.debug('EVENT: PLAYER LEFT_UNIT: ' .. unitName)
			tms.deletePlayer(event.initiator:getName())
			tms.stopSchedule()
		end
	
	--@ player left unit by ejecting
	elseif event.id == world.event.S_EVENT_EJECTION then
		local unitName = event.initiator:getName()
		if event.initiator ~= nil and ifHuman(unitName) and playerDetails[unitName].active == true then
			tms.debug('EVENT: HUMAN_PLAYER_EJECTED: ' .. unitName)
			tms.deletePlayer(unitName)
			tms.stopSchedule()
		end
	
	--@ a unit or a player died
	elseif event.id == world.event.S_EVENT_DEAD or
	event.id == world.event.S_EVENT_PILOT_DEAD or
	event.id == world.event.S_EVENT_CRASH then
	--tms.debug('EVENT DEAD ID: ' .. tostring(event.id) .. ' Initiator:' .. tostring(event.initiator))
		if event.initiator ~= nil then
			local unitName = event.initiator:getName()
			-- if it is a player
			if ifHuman(unitName) and playerDetails[unitName].active == true then
				tms.debug('EVENT: HUMAN_PLAYER DEAD/CRASHED: ' .. unitName)
				tms.deletePlayer(unitName)
				tms.stopSchedule()
			-- if it is an AI unit
			elseif not ifHuman(unitName) then
				if not unitIsDead[unitName] then 
					unitIsDead[unitName] = true
			-- now we have to check if it isn't a MAPOBJECT
					if ifObject(unitName) then
						tms.debug('EVENT: MAPOBJECT_DEAD: ' .. unitName)
					elseif not ifObject(unitName) then
						tms.debug('EVENT: AI_UNIT DEAD: ' .. unitName)
						tms.checkDeadGroup(unitName)
					end
			-- seems this AI unit was already recognized as dead unit 
				elseif unitIsDead[unitName] then 
					tms.debug('EVENT: AI_UNIT IS ALREADY DEAD: ' .. unitName .. ' no further actions!') 
				end
			end
		end
		
	--@ catch the event on who shots who...	
	-- elseif event.id == world.event.S_EVENT_HIT then
		-- local weapon = event.weapon
		-- if event.initiator ~= nil then
			-- local unitName = event.initiator:getName()
			-- local targetName = event.target:getName()
			-- if not weaponTbl then weaponTbl = {} end
			-- table.insert(weaponTbl, weapon)
			-- tms.debug('EVENT: HIT: ' .. unitName .. ' hits ' .. targetName) -- .. ' with weapon: ' .. tostring(weapon))
		-- end
	end
end

do
	for i, side in pairs(sideTbl) do
		-- we need to make an randomized table of the task
		task[side].randomNumTable = mist.randomizeNumTable({size=tms[side]})
		for j, role in pairs(roleTbl) do
			for taskNr=1, tms[side] do
				local taskNrString = '#' .. string.format('%02d', taskNr)
				-- fetch all groupnames that have to be activated
				for groupName, v in pairs(mist.DBs.groupsByName) do
				--local groupName = next(mist.DBs.groupsByName)
				--repeat
					if string.match(groupName, side) and string.match(groupName, role) and string.match(groupName, taskNrString) then
						table.insert(task[side][role][taskNr].groups, groupName) -- store the "Groups" in global table for later use
						if string.match(groupName,'target') then
							task[side][role][taskNr].target = task[side][role][taskNr].target + Group.getByName(groupName):getInitialSize()
						elseif string.match(groupName,'allied') then
							task[side][role][taskNr].allied = task[side][role][taskNr].allied + Group.getByName(groupName):getInitialSize()
						end
					end
					--groupName = next(mist.DBs.groupsByName, groupName)
				--until groupName == nil
				end
			end
		end
	end
	event_tms = mist.addEventHandler(tms.eventHandler)
end