--[[ Copyright (c) 2009 Peter "Corsix" Cawley

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE. --]]

class "HeatingController"

---@type HeatingController
local HeatingController = _G["HeatingController"]

local COLD_TOLERANCE_TEMP = 0.22
local HOT_TOLERANCE_TEMP = 0.36
local DEFAULT_DAYS_UNTIL_BOILER_BREAKDOWN = 200

function HeatingController:HeatingController(world)
  self.world = world
  self:setRadiatorHeat(0.5)
  self:resetBoilerBreakdownCounter()
  self.acc_heating = 0
  self.heating_broke = false
  self.boiler_can_break = true
  self.warmth_msg = false
end

function HeatingController:resetBoilerBreakdownCounter()
  self.days_until_boiler_breakdown = self.world.map.level_config.gbv.DisasterLaunch
  --if disasterLaunch not defined in Levelfile
  if self.days_until_boiler_breakdown == nil then
    self.days_until_boiler_breakdown = DEFAULT_DAYS_UNTIL_BOILER_BREAKDOWN
  end
end

function HeatingController:checkHeatingFacilities(isPlayerHospital,day,averagePatiensWarmth, averageStaffWarmth)
  if not self.warmth_msg and not self.heating_broke then
    if day == 15 then
      if averagePatiensWarmth < COLD_TOLERANCE_TEMP then
        self:warningTooCold(isPlayerHospital)
      elseif averagePatiensWarmth >= HOT_TOLERANCE_TEMP then
        self:warningTooHot(isPlayerHospital)
      end
    end
    -- Are the staff warm enough?
    if day == 20 then
      if averageStaffWarmth < COLD_TOLERANCE_TEMP then
        if isPlayerHospital == true then
          self.world.ui.adviser:say(_A.warnings.staff_very_cold)
        end
        self.warmth_msg = true
      elseif averageStaffWarmth >= HOT_TOLERANCE_TEMP then
        if isPlayerHospital == true then
          self.world.ui.adviser:say(_A.warnings.staff_too_hot)
        end
        self.warmth_msg = true
      end
    end
  end
end

function HeatingController:warningTooCold(isPlayerHospital)
  if isPlayerHospital == true then
    local cold_msg = {
      (_A.information.initial_general_advice.increase_heating),
      (_A.warnings.patients_very_cold),
      (_A.warnings.people_freezing),
    }
    self.world.ui.adviser:say(cold_msg[math.random(1, #cold_msg)])
  end
  self.warmth_msg = true
end

function HeatingController:warningTooHot(isPlayerHospital)
  if isPlayerHospital == true then
    local hot_msg = {
      (_A.information.initial_general_advice.decrease_heating),
      (_A.warnings.patients_too_hot),
      (_A.warnings.patients_getting_hot),
    }
    self.world.ui.adviser:say(hot_msg[math.random(1, #hot_msg)])
  end
  self.warmth_msg = true
end

function HeatingController:resetWarmthMsgFlag()
  self.warmth_msg = false
end

function HeatingController:afterLoad(old,new)
  if old < 125 then
    self:resetBoilerBreakdownCounter()
  end
end

function HeatingController:coldWarning()
  local announcements = {
    "sorry002.wav", "sorry004.wav",
  }
  self.world.ui:playAnnouncement(announcements[math.random(1, #announcements)])
end

function HeatingController:hotWarning()
  local announcements = {
    "sorry003.wav", "sorry004.wav",
  }
  self.world.ui:playAnnouncement(announcements[math.random(1, #announcements)])
end

-- Called when the hospitals's boiler has broken down.
-- It will remain broken for a certain period of time.
function HeatingController:boilerBreakdown(isPlayerHospital)
  self.curr_setting = self.radiator_heat
  self:setRadiatorHeat(math.random(0, 1))
  self.boiler_countdown = math.random(10, 30)

  self.heating_broke = true

  -- Only show the message when relevant to the local player's hospital.
  if isPlayerHospital == true then
    if self.radiator_heat == 0 then
      self.world.ui.adviser:say(_A.boiler_issue.minimum_heat)
      self:coldWarning()
    else
      self.world.ui.adviser:say(_A.boiler_issue.maximum_heat)
      self:hotWarning()
    end
  end
end

-- When the boiler has been repaired this function is called.
function HeatingController:boilerFixed(isPlayerHospital)
  self:setRadiatorHeat(self.curr_setting)
  self.heating_broke = false
  self:resetBoilerBreakdownCounter()
  if isPlayerHospital == true then
    self.world.ui.adviser:say(_A.boiler_issue.resolved)
  end
end

function HeatingController:onEndDay(nbHandyman, isPlayerHospital)
  --variables for heating
  local radiators = self.world.object_counts.radiator

  if nbHandyman == false then
    nbHandyman = 0
  end

  -- Countdown for boiler breakdowns
  if self.heating_broke then
    if 5 * nbHandyman >= radiators and self.boiler_countdown > 3 then
      self.boiler_countdown = self.boiler_countdown - 3
    elseif 8 * nbHandyman >= radiators and self.boiler_countdown > 2 then
      self.boiler_countdown = self.boiler_countdown - 2
    else
      self.boiler_countdown = self.boiler_countdown - 1
    end
    if self.boiler_countdown == 0 then
      self:boilerFixed(isPlayerHospital)
    end
  end

  -- Is the boiler working today?
  if self.days_until_boiler_breakdown <= 0 then
    self:resetBoilerBreakdownCounter()
    --33% chance nothing happen 66% Boiler breakdown
    --Todo: 50% chance boiler breakdown, 25% chance vomit wave, 25% change nothing happen
    if math.random(1,3) ~= 1 then
      --check if boiler can break
      if not self.heating_broke and self.boiler_can_break and radiators > 0 and 8 * nbHandyman < radiators then
        self:boilerBreakdown(isPlayerHospital)
      end
    end
  else
    self.days_until_boiler_breakdown = self.days_until_boiler_breakdown - 1
  end

  -- Calculate heating cost daily.  Divide the monthly cost by the number of days in that month
  local heating_costs = self:calculateExpectedMonthlyHeatingCosts() / self.world:date():lastDayOfMonth()
  self.acc_heating = self.acc_heating + heating_costs
end

function HeatingController:calculateExpectedMonthlyHeatingCosts()
  local radiators = self.world.object_counts.radiator
  return (((self.radiator_heat * 10) * radiators) * 7.50)
end

function HeatingController:getHeatingCostsForActualMonth()
  return math.floor(self.acc_heating + 0.5)
end

function HeatingController:resetHeatingCostsForActualMonth()
  self.acc_heating = 0
end

function HeatingController:getRadiatorHeat()
  return self.radiator_heat
end

function HeatingController:setRadiatorHeat(newValue)
  if newValue > 1 then
    newValue = 1
  elseif newValue < 0 then
    newValue = 0
  end
  self.radiator_heat = newValue
end

function HeatingController:decreaseHeat()
  local heat = math.floor(self.radiator_heat * 10 + 0.5)
  if not self.heating_broke then
    heat = heat - 1
    if heat < 1 then
      heat = 1
    end
    self:setRadiatorHeat(heat / 10)
  end
end

function HeatingController:increaseHeat()
  local heat = math.floor(self.radiator_heat * 10 + 0.5)
  if not self.heating_broke then
    heat = heat + 1
    if heat > 10 then
      heat = 10
    end
    self:setRadiatorHeat(heat / 10)
  end
end
