local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local WS         = workspace
local LP         = Players.LocalPlayer
local CS         = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Lighting   = game:GetService("Lighting")

local DISCORD_INVITE = "https://discord.gg/FJK6QzNnf7"
local CREDIT_NAME    = "Cathub_MEOW"

local CFG = { Poll=0.25, TeleportWait=0.5, MaxPerGame=45, EyeDebounce=0.15, EyeBrute=false }

local POS = {
    Basketball=Vector3.new(65.986,38.742,-84.227), PopTheBalloon=Vector3.new(-255.939,14.934,-103.819),
    DunkBooth=Vector3.new(-87.302,16.232,101.158), MiniGolf=Vector3.new(24.744,9.068,115.494),
    ["High Striker"]=Vector3.new(-31.978,32.859,28.214), RingToss=Vector3.new(-325.75,17.284,141.52),
    WhackAClown=Vector3.new(-63.946,17.123,-150.882), Puzzle1=Vector3.new(1575.572,-43.723,4276.123),
    Puzzle2=Vector3.new(1818.316,-67.9,4526.75), Puzzle3=Vector3.new(1683.405,-45.787,4499.757),
    Puzzle4=Vector3.new(1830.749,-63.622,4599.413), CrystalBallWish=Vector3.new(1848.402,-65.07,4345.935),
}
local PROMPT_PATH = {
    Basketball="PromptPart", PopTheBalloon="Camera", DunkBooth="ProxPart",
    MiniGolf="ProxPart", ["High Striker"]="ProxPart", RingToss="ring", WhackAClown="Hammer",
}

local function root() local c=LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function tp(v) local r=root(); if r and v then r.CFrame=CFrame.new(v); r.AssemblyLinearVelocity=Vector3.zero; r.AssemblyAngularVelocity=Vector3.zero end end
local function games() local s=WS:FindFirstChild("Section1"); return s and s:FindFirstChild("Games") end
local function mainObj() local s=WS:FindFirstChild("Section2"); return s and s:FindFirstChild("MainObjective") end
local function promptOf(i,h)
    if not i then return nil end
    if h then
        local c=i:FindFirstChild(h,true)
        if c then
            if c:IsA("ProximityPrompt") then return c end
            local p=c:FindFirstChild("ProximityPrompt",true) or c:FindFirstChildWhichIsA("ProximityPrompt",true)
            if p then return p end
        end
    end
    return i:FindFirstChildWhichIsA("ProximityPrompt",true)
end
local function promptPos(p)
    local a=p.Parent
    if a:IsA("Attachment") then return a.WorldPosition end
    if a:IsA("BasePart") then return a.Position end
    if a:IsA("Model") then return a:GetPivot().Position end
end
-- exact same press sequence as the working script: aim camera -> hold -> aim -> instant prompts -> hold
local savedHold={}
local function instantPrompts(on)
    if on then
        for _,d in ipairs(WS:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                if savedHold[d]==nil then savedHold[d]=d.HoldDuration end
                d.HoldDuration=0
            end
        end
    else
        for p,h in pairs(savedHold) do if p.Parent then pcall(function() p.HoldDuration=h end) end end
        table.clear(savedHold)
    end
end
local function aimAt(cam,pos)
    cam.CameraType=Enum.CameraType.Scriptable
    cam.CFrame=CFrame.lookAt(cam.CFrame.Position,pos)
    cam.Focus=CFrame.new(pos)
    RunService.RenderStepped:Wait()
    task.wait(0.15)
end
local function firePrompt(p)
    if not p or not p:IsA("ProximityPrompt") then return false end
    local cam=WS.CurrentCamera
    if not cam then return false end
    local saved={cam.CameraType==Enum.CameraType.Scriptable and Enum.CameraType.Custom or cam.CameraType,cam.CameraSubject,cam.CFrame,cam.Focus}
    local pos=promptPos(p) or (cam.CFrame.Position+cam.CFrame.LookVector*10)
    local held=false
    local ok,err=pcall(function()
        aimAt(cam,pos)
        p:InputHoldBegin() held=true task.wait(0.1) p:InputHoldEnd() held=false
        task.wait(0.15)
        aimAt(cam,pos)
        instantPrompts(true)
        p:InputHoldBegin() held=true task.wait(0.12) p:InputHoldEnd() held=false
        task.wait(0.15)
    end)
    if held then pcall(function() p:InputHoldEnd() end) end
    instantPrompts(false)
    pcall(function() cam.CameraType=saved[1] cam.CameraSubject=saved[2] cam.CFrame=saved[3] cam.Focus=saved[4] end)
    if not ok then
        warn("[Mimic] InputHold failed: "..tostring(err))
        if fireproximityprompt then pcall(fireproximityprompt,p) end
    end
    return ok
end

-- game counts as started when any of its attributes changed after the press, or the prompt went away
local function snap(inst) local t={} for k,v in pairs(inst:GetAttributes()) do t[k]=v end return t end
local function changed(inst,before)
    local now=inst:GetAttributes()
    for k,v in pairs(now) do if before[k]~=v then return true end end
    for k in pairs(before) do if now[k]==nil then return true end end
    return false
end
local function startGame(inst,p,ctl)
    if not p then warn("[Mimic] prompt not found for "..inst.Name) return false end
    print("[Mimic] pressing prompt:", p:GetFullName())
    for i=1,3 do
        if not ctl.Running then return false end
        local before=snap(inst)
        firePrompt(p)
        task.wait(0.4)
        if changed(inst,before) or p.Parent==nil or p.Enabled==false then return true end
        task.wait(0.6)
    end
    warn("[Mimic] start not confirmed for "..inst.Name..", running anyway")
    return false
end

-- float + noclip (same idea as the working script) so the char doesn't fall/get pushed after tp
-- original CanCollide values are saved and restored on floatOff, so the char never falls through the map
local floatState
local function floatOn()
    local r=root() if not r then return end
    if floatState and floatState.bv.Parent==r then return end
    if floatState then pcall(function() floatState.nc:Disconnect() floatState.bv:Destroy() end) end
    local orig={}
    local c=LP.Character
    if floatState then orig=floatState.orig end
    if c then for _,d in ipairs(c:GetDescendants()) do if d:IsA("BasePart") and orig[d]==nil then orig[d]=d.CanCollide end end end
    local bv=Instance.new("BodyVelocity") bv.Name="MimicFloat" bv.MaxForce=Vector3.new(0,math.huge,0) bv.Velocity=Vector3.zero bv.P=10000 bv.Parent=r
    local nc=RunService.Stepped:Connect(function()
        local ch=LP.Character
        if ch then for _,d in ipairs(ch:GetDescendants()) do if d:IsA("BasePart") then d.CanCollide=false end end end
    end)
    floatState={bv=bv,nc=nc,orig=orig}
end
local function floatOff()
    local st=floatState
    floatState=nil
    if not st then return end
    pcall(function() st.nc:Disconnect() end)
    pcall(function() st.bv:Destroy() end)
    for part,was in pairs(st.orig) do
        if part.Parent then pcall(function() part.CanCollide=was end) end
    end
end

local okPacket, PACKET = pcall(function() return require(RS:WaitForChild("modules"):WaitForChild("Packet")) end)
if not okPacket then PACKET = nil end
local function reliable() local m=RS:FindFirstChild("modules") local p=m and m:FindFirstChild("Packet") return p and p:FindFirstChild("Reliable") end
local REMOTE = reliable()

local function waitForGames(t) local t0=os.clock() while os.clock()-t0<(t or 25) do local g=games(); if g then return g end task.wait(0.25) end end
local function waitForPuzzle(n,t) local t0=os.clock() while os.clock()-t0<(t or 25) do local mo=mainObj(); local p=mo and mo:FindFirstChild(n); if p then return p end task.wait(0.2) end end

local loops = {}
local function stopLoop(n) local l=loops[n]; if l then l.Running=false; loops[n]=nil end end
local function startLoop(n,fn) stopLoop(n) local c={Running=true} loops[n]=c task.spawn(function() local ok,err=pcall(fn,c) if not ok then warn("[Mimic "..n.."] "..tostring(err)) end c.Running=false if loops[n]==c then loops[n]=nil end end) end

local ticks={}
local notes={}  -- last result per game, shown in the GUI row
-- get the player back: leave the minigame, restore camera/controls, drop float, go to the safe zone
local gameActive=false
local SAFE=Vector3.new(-135.193,28.701,-50.983)
local SAFE_HOLLOW=Vector3.new(-523.016,13.935,489.681)
local function isHollow()
    if WS:GetAttribute("MimicHollowOptedOut")==true then return false end
    if WS:GetAttribute("MimicHollowSelected")==true then return true end
    return WS:GetAttribute("MimicEvent")=="TheHollow"
end
local function safeZone()
    return isHollow() and SAFE_HOLLOW or SAFE
end
-- Section 1 games go back to the safe zone (like Prometheus). Tent puzzles are in a different area,
-- so they go back to where the player stood before starting, never to the Section 1 coordinates (that is the void there).
local origin, lastTent=nil, false
local function goBack()
    local r=root()
    if lastTent then
        if r and origin then r.CFrame=origin r.AssemblyLinearVelocity=Vector3.zero r.AssemblyAngularVelocity=Vector3.zero end
    else
        tp(safeZone())
    end
end
local function pressLeave()
    local pg=LP:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    for _,d in ipairs(pg:GetDescendants()) do
        if (d:IsA("TextButton") or d:IsA("TextLabel")) and d.Visible then
            local t=(string.gsub(string.upper(d.Text),"%s",""))
            if t=="LEAVE" then
                local b=d:IsA("GuiButton") and d or d:FindFirstAncestorWhichIsA("GuiButton")
                if b and b.Visible then
                    if firesignal then pcall(firesignal,b.MouseButton1Click) pcall(firesignal,b.Activated) pcall(firesignal,b.MouseButton1Down) pcall(firesignal,b.MouseButton1Up) end
                    if getconnections then
                        for _,sig in ipairs({b.MouseButton1Click,b.Activated}) do
                            local okc,conns=pcall(getconnections,sig)
                            if okc and conns then for _,c in ipairs(conns) do pcall(function() c:Fire() end) end end
                        end
                    end
                end
            end
        end
    end
end
local function restoreControl()
    local cam=WS.CurrentCamera
    local c=LP.Character
    local h=c and c:FindFirstChildOfClass("Humanoid")
    if cam then
        cam.CameraType=Enum.CameraType.Custom
        if h then cam.CameraSubject=h end
    end
    if h then
        h.PlatformStand=false
        h.Sit=false
        pcall(function() h:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
end
local function unstuck(force)
    for n in pairs(loops) do stopLoop(n) end
    for k in pairs(ticks) do ticks[k]=false end
    floatOff()
    if PACKET and PACKET.send and PACKET.send.Section1 and PACKET.send.Section1.HighStrikerLeave then pcall(PACKET.send.Section1.HighStrikerLeave) end
    if force or gameActive then pressLeave() end
    gameActive=false
    task.wait(0.15)
    restoreControl()
    goBack()
    task.wait(0.1)
    restoreControl()
end

local runners = {}

runners.Basketball = function(inst,ctl)
    if not PACKET then return end
    local pkt=PACKET.send.Section1
    while ctl.Running and inst:GetAttribute("Complete")~=true do
        if inst:GetAttribute("Phase")=="idle" then
            pcall(pkt.BasketballHold)
            local t0=os.clock() while ctl.Running and os.clock()-t0<1 do task.wait() end
            local dur=os.clock()-t0
            pcall(function() pkt.BasketballRelease(dur) end)
            local t1=os.clock()
            while ctl.Running and inst:GetAttribute("Complete")~=true and inst:GetAttribute("Phase")=="idle" and os.clock()-t1<2 do task.wait(0.05) end
        else task.wait(0.1) end
    end
end

runners.PopTheBalloon = function(inst,ctl)
    if not PACKET then return end
    local T={
        {-0.8302127029982302,0.858834508939232},{-0.34659015274423904,0.827476804554531},
        {-0.014494814317703903,0.8364363212223435},{0.423985455702752,0.9484285482390907},
        {0.8044402336831856,0.9529078636743922},{-0.8560072541585854,0.08384543182541498},
        {-0.42074475654122223,0.04352810508118887},{-0.06286139171218387,0.030089008748793566},
        {0.49169604382818577,0.039048203308529886},{0.9011664245043618,0.012169799260314236},
        {-0.862456138268471,-0.8927305054917737},{-0.38850114739818375,-0.8120959828597274},
        {-0.05641298575249203,-0.8031367882999911},{0.5594041977344515,-0.8389746133901842},
        {0.8495776699292469,-0.888250948475415},
    }
    local pkt=PACKET.send.Section1
    local balloons=inst:FindFirstChild("Balloons")
    while ctl.Running and inst:GetAttribute("Complete")~=true do
        local order={}
        if balloons then
            for _,b in ipairs(balloons:GetChildren()) do if b:IsA("BasePart") then table.insert(order,b) end end
            table.sort(order,function(a,b) if math.abs(a.Position.Y-b.Position.Y)>1 then return a.Position.Y>b.Position.Y end return a.Position.X<b.Position.X end)
        end
        local any=false
        for _,b in ipairs(order) do if b:GetAttribute("Popped")~=true then any=true break end end
        if not any then task.wait(0.2) continue end
        for i,b in ipairs(order) do
            if not ctl.Running then break end
            if b:GetAttribute("Popped")~=true and T[i] then pcall(function() pkt.DartsThrow(T[i][1],T[i][2]) end) task.wait(0.05) end
        end
        task.wait(0.05)
    end
end

runners.DunkBooth = function(inst,ctl)
    if not REMOTE then return end
    while ctl.Running and inst:GetAttribute("Complete")~=true do pcall(function() REMOTE:FireServer("Section1/DunkThrow",0,0) end) task.wait(0.55) end
end

runners.MiniGolf = function(inst,ctl)
    if not PACKET then return end
    local ball=inst:FindFirstChild("GolfBall") local hole=inst:FindFirstChild("Hole") if not ball or not hole then return end
    local pkt=PACKET.send.Section1 local last=0
    while ctl.Running and inst:GetAttribute("Complete")~=true do
        if os.clock()-last>=0.5 then
            last=os.clock()
            local d=hole.Position-ball.Position local flat=Vector3.new(d.X,0,d.Z)
            if flat.Magnitude>0.05 then
                local dir=flat.Unit local dist=flat.Magnitude local power=math.clamp(dist/60,0.1,1)
                ball.AssemblyLinearVelocity=dir*(power*100)
                pcall(function() pkt.MiniGolfShot(dir,power) end)
            end
        end
        task.wait(0.05)
    end
end

runners["High Striker"] = function(inst,ctl)
    if not REMOTE then return end
    local booth=POS["High Striker"] local prompt=promptOf(inst,"ProxPart") local danger,resume=40,60
    local function distTo(pos)
        local s1=WS:FindFirstChild("Section1") local m=s1 and s1:FindFirstChild("Monster") local r=m and m:FindFirstChild("Ronnie")
        local p=r and (r:IsA("BasePart") and r.Position or (r:FindFirstChild("HumanoidRootPart") or r.PrimaryPart) and (r:FindFirstChild("HumanoidRootPart") or r.PrimaryPart).Position)
        return p and (p-pos).Magnitude or math.huge
    end
    local function dangerNow() local r=root() return not r or distTo(r.Position)<=danger or distTo(booth)<=danger end
    local function retreat() if PACKET and PACKET.send.Section1.HighStrikerLeave then pcall(PACKET.send.Section1.HighStrikerLeave) end tp(Vector3.new(-135.193,28.701,-50.983)) end
    while ctl.Running and inst:GetAttribute("Complete")~=true do
        if dangerNow() then
            retreat()
            local t0=os.clock() while ctl.Running and distTo(booth)<resume and os.clock()-t0<10 do task.wait(0.15) end
        else
            tp(booth) task.wait(0.4)
            if not dangerNow() then
                local ph=inst:GetAttribute("Phase")
                if ph~="idle" and ph~="windup" and ph~="slam" then firePrompt(prompt) task.wait(0.3) end
                local t0=os.clock()
                while ctl.Running and not dangerNow() and os.clock()-t0<CFG.MaxPerGame do
                    local p=inst:GetAttribute("Phase")
                    if p=="idle" or p=="windup" then pcall(function() REMOTE:FireServer("Section1/HighStrikerClick") end) end
                    if inst:GetAttribute("Complete")==true then break end
                    task.wait(0.05)
                end
            end
        end
        task.wait(0.2)
    end
end

runners.RingToss = function(inst,ctl)
    if not REMOTE then return end
    local T={
        {-0.7599205563588964,0.05620804191990332},{-0.33349659719571545,0.05176755345680496},
        {0.02020419993316347,0.05844950845295732},{0.48298954213791445,0.08154461498964916},
        {0.6383536509072825,0.055650840090079735},{-0.009546382510995599,0.31133286824280565},
    }
    local bottles=inst:FindFirstChild("Bottles")
    while ctl.Running and inst:GetAttribute("Complete")~=true do
        local left=0
        if bottles then for _,b in ipairs(bottles:GetChildren()) do if b:IsA("BasePart") and b:GetAttribute("Ringed")~=true then left+=1 end end end
        if left==0 then task.wait(0.4) continue end
        for _,t in ipairs(T) do
            if not ctl.Running or inst:GetAttribute("Complete")==true then break end
            pcall(function() REMOTE:FireServer("Section1/RingThrow",t[1],t[2]) end)
            task.wait(1)
        end
    end
end

runners.WhackAClown = function(inst,ctl)
    if not REMOTE then return end
    local clowns=inst:FindFirstChild("Clowns") local last={}
    while ctl.Running and inst:GetAttribute("Complete")~=true do
        local any=false
        if clowns then
            for _,c in ipairs(clowns:GetChildren()) do
                if c:IsA("Model") and c:GetAttribute("Active")==true then
                    any=true local now=os.clock()
                    if now-(last[c] or 0)>=0.13 then last[c]=now pcall(function() REMOTE:FireServer("Section1/Whack",c) end) end
                end
            end
        end
        task.wait(any and 0.03 or 0.1)
    end
end

local function runPacketPuzzle(objName,packetName,waitComplete,ctl)
    local obj=waitForPuzzle(objName,20) if not obj then return end
    tp(POS[objName]) task.wait(CFG.TeleportWait)
    firePrompt(promptOf(obj,"PromptPart")) task.wait(0.5)
    if not (PACKET and PACKET.send.Section2[packetName]) then return end
    local t0=os.clock()
    while ctl.Running and os.clock()-t0<CFG.MaxPerGame do
        local sent=pcall(PACKET.send.Section2[packetName])
        if obj:GetAttribute("Complete")==true then break end
        -- like Prometheus: for puzzles that don't need repeating, send once and then just wait for Complete
        if sent and not waitComplete then break end
        task.wait(0.5)
    end
    while ctl.Running and obj.Parent and obj:GetAttribute("Complete")~=true and os.clock()-t0<CFG.MaxPerGame do task.wait(0.1) end
end

runners.Puzzle1 = function(_,ctl) runPacketPuzzle("Puzzle1","StarPuzzleComplete",false,ctl) end
runners.Puzzle3 = function(_,ctl) runPacketPuzzle("Puzzle3","MoonPuzzleComplete",true,ctl) end
runners.Puzzle4 = function(_,ctl) runPacketPuzzle("Puzzle4","TarotPuzzleComplete",false,ctl) end

runners.Puzzle2 = function(_,ctl)
    local obj=waitForPuzzle("Puzzle2",20) if not obj then return end
    tp(POS.Puzzle2) task.wait(CFG.TeleportWait)
    local mirrors=obj:WaitForChild("Mirrors",10) local statues=obj:WaitForChild("EyeStatues",10)
    if not mirrors or not statues then warn("[Mimic] eye puzzle: Mirrors/EyeStatues missing") return end
    local map=isHollow() and {4,3,2,1} or {1,2,3,4}
    local st={Recording=true,Seq={},Last=0}
    local conns,flipped,lastFlash={}, {}, {}
    -- 1) hook the mirrors BEFORE starting, same order as Prometheus
    for i=1,4 do
        local m=mirrors:FindFirstChild("Mirror"..i) local eye=m and m:FindFirstChild("Eye") local part=eye and eye:FindFirstChild("Part")
        if part and part:IsA("BasePart") then
            flipped[i]=part.Transparency<0.5
            table.insert(conns,part:GetPropertyChangedSignal("Transparency"):Connect(function()
                local vis=part.Transparency<0.5
                if vis and not flipped[i] then
                    local now=os.clock()
                    if now-(lastFlash[i] or 0)>=CFG.EyeDebounce then
                        lastFlash[i]=now
                        if st.Recording then table.insert(st.Seq,i) st.Last=now end
                    end
                end
                flipped[i]=vis
            end))
        end
    end
    local function cleanup() for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end end
    local ok,err=pcall(function()
        -- 2) press the start prompt (Prometheus does this for the eye puzzle too)
        firePrompt(promptOf(obj,"PromptPart"))
        local startTries=0
        -- 3) rounds: record the flashing sequence, then press the statues in that order, repeat until Complete
        while ctl.Running and obj.Parent and obj:GetAttribute("Complete")~=true do
            st.Seq={} st.Last=0 st.Recording=true
            local t0=os.clock()
            while ctl.Running and obj:GetAttribute("Complete")~=true do
                if #st.Seq>0 and os.clock()-st.Last>=2 then break end
                if #st.Seq==0 and os.clock()-t0>25 then break end
                task.wait(0.1)
            end
            st.Recording=false
            if not ctl.Running or obj:GetAttribute("Complete")==true then break end
            local seq=st.Seq
            if #seq==0 then
                startTries+=1
                if startTries<=2 then
                    warn("[Mimic] eye puzzle: no flashes seen, pressing start again")
                    firePrompt(promptOf(obj,"PromptPart"))
                else
                    warn("[Mimic] eye puzzle: no flashes, trying every statue in order")
                    for _,order in ipairs({{1,2,3,4},{4,3,2,1}}) do
                        for _,i in ipairs(order) do
                            if not ctl.Running or obj:GetAttribute("Complete")==true then break end
                            firePrompt(promptOf(statues:FindFirstChild("Eye"..i))) task.wait(0.4)
                        end
                    end
                    break
                end
            else
                print("[Mimic] eye sequence:", table.concat(seq,","), "hollow:", tostring(isHollow()))
                for _,i in ipairs(seq) do
                    if not ctl.Running or obj:GetAttribute("Complete")==true then break end
                    local statue=statues:FindFirstChild("Eye"..map[i])
                    local prompt=statue and promptOf(statue)
                    if prompt then
                        local t1=os.clock()
                        while ctl.Running and prompt.Enabled==false and os.clock()-t1<3 do task.wait(0.1) end
                        local hit=false
                        local c=prompt.Triggered:Connect(function() hit=true end)
                        for _=1,3 do
                            if hit or not ctl.Running then break end
                            firePrompt(prompt)
                            task.wait(0.2)
                        end
                        c:Disconnect()
                    else
                        warn("[Mimic] eye puzzle: missing prompt on Eye"..tostring(map[i]))
                    end
                end
                task.wait(0.5)
            end
        end
    end)
    cleanup()
    if not ok then warn("[Mimic] eye puzzle error: "..tostring(err)) notes.Puzzle2="error" end
end

runners.CrystalBallWish = function(_,ctl)
    local obj=waitForPuzzle("CrystalBallWish",20) if not obj then return end
    tp(POS.CrystalBallWish) task.wait(CFG.TeleportWait)
    firePrompt(promptOf(obj,"PromptPart"))
    local t0=os.clock()
    while ctl.Running and os.clock()-t0<CFG.MaxPerGame do
        if obj:GetAttribute("Complete")==true then break end
        task.wait(0.25)
    end
end

local boss={Running=false,SpeedConn=nil}
local function bosses() local list={} for _,m in ipairs(CS:GetTagged("AI_DimitraBoss")) do if m:IsA("Model") and m.Parent then local h=m:FindFirstChildOfClass("Humanoid") if h and h.Health>0 then table.insert(list,m) end end end return list end
local function bossPos(m) local r=m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart",true) return r and r.Position end
local function nearestBoss(from) local best,dist=nil,math.huge for _,m in ipairs(bosses()) do local p=bossPos(m) if p then local d=(p-from).Magnitude if d<dist then best,dist=m,d end end end return best,dist end
local function bossAttack(m) if not REMOTE then return end pcall(function() REMOTE:FireServer("Arena/BossAttack",m) end) pcall(function() REMOTE:FireServer("Section1/ArenaBossAttack",m) end) end
local function bossStart()
    if boss.Running then return end
    boss.Running=true
    boss.SpeedConn=RunService.Heartbeat:Connect(function()
        if not boss.Running then return end
        local c=LP.Character if not c then return end
        local h=c:FindFirstChildOfClass("Humanoid") local r=c:FindFirstChild("HumanoidRootPart")
        if not h or not r or h.Health<=0 then return end
        local mv=h.MoveDirection if mv.Magnitude>0.01 then r.CFrame=r.CFrame+mv*3 end
    end)
    task.spawn(function()
        while boss.Running do
            local r=root()
            if r then local m,d=nearestBoss(r.Position) if m then if d and d>12 then tp(bossPos(m)+Vector3.new(0,3,3)) end bossAttack(m) end end
            task.wait(0.1)
        end
    end)
end
local function bossStop() boss.Running=false if boss.SpeedConn then boss.SpeedConn:Disconnect() boss.SpeedConn=nil end end
CS:GetInstanceAddedSignal("AI_DimitraBoss"):Connect(function(m) if m:IsA("Model") then task.wait(1) bossStart() end end)
CS:GetInstanceRemovedSignal("AI_DimitraBoss"):Connect(function() task.spawn(function() task.wait(2) if #bosses()==0 then bossStop() end end) end)

local ORDER_S1={"Basketball","PopTheBalloon","DunkBooth","MiniGolf","High Striker","RingToss","WhackAClown"}
local ORDER_S2={"Puzzle1","Puzzle3","Puzzle4","Puzzle2","CrystalBallWish"}
local LABEL_S1={
    Basketball="Basketball",PopTheBalloon="Balloon Dart",DunkBooth="Dunk Ball",
    MiniGolf="MiniGolf",["High Striker"]="High Striker",RingToss="Ring Toss",WhackAClown="Whack a Clown",
}
local LABEL_S2={Puzzle1="Star Puzzle",Puzzle2="Eye Puzzle",Puzzle3="Moon Puzzle",Puzzle4="Tarot Puzzle",CrystalBallWish="Crystal Ball"}


local function runOne(name,ctl)
    notes[name]=nil
    local isTent=name:sub(1,6)=="Puzzle" or name=="CrystalBallWish"
    local inst
    if isTent then inst=waitForPuzzle(name,20)
    else local g=waitForGames(20) inst=g and g:WaitForChild(name,10) end
    if not inst then notes[name]="not found" return end
    -- load Packet/Reliable late if they weren't ready when the script started
    if not PACKET then pcall(function() PACKET=require(RS:WaitForChild("modules",5):WaitForChild("Packet",5)) end) end
    if not REMOTE then REMOTE=reliable() end
    if not PACKET then notes[name]="no packet" warn("[Mimic] Packet module not loaded") end
    if not gameActive then local r0=root() origin=r0 and r0.CFrame or origin end
    lastTent=isTent
    floatOn()
    gameActive=true
    if POS[name] then tp(POS[name]) task.wait(CFG.TeleportWait) end
    local r=runners[name]
    if isTent or name=="High Striker" then
        -- these runners press their own prompt
        if r then r(inst,ctl) end
    else
        -- same order as the working script: start the runner first, then press the prompt
        local done=false
        task.spawn(function()
            local ok,err=pcall(r,inst,ctl)
            if not ok then warn("[Mimic "..name.."] "..tostring(err)) notes[name]="error" end
            done=true
        end)
        startGame(inst,promptOf(inst,PROMPT_PATH[name]),ctl)
        while ctl.Running and not done do task.wait(0.1) end
    end
    if not notes[name] then notes[name]=(inst:GetAttribute("Complete")==true) and "✓ done" or "stopped" end
    -- finished on its own (not stopped by the user): leave the game and go back to the safe zone
    if ctl.Running then
        pressLeave()
        gameActive=false
        floatOff()
        restoreControl()
        goBack()
    end
end

local function runSelected(scope)
    local list=scope=="s1" and ORDER_S1 or ORDER_S2
    for _,name in ipairs(list) do
        if ticks[name] then
            startLoop(name,function(ctl) runOne(name,ctl) end)
            local t0=os.clock()
            while loops[name] and loops[name].Running and ticks[name] and os.clock()-t0<180 do task.wait(0.25) end
            if loops[name] and loops[name].Running then
                -- timed out: stop this game cleanly before the next one starts
                stopLoop(name)
                pressLeave()
                floatOff()
                restoreControl()
                goBack()
                gameActive=false
            end
        end
    end
    floatOff()
end

local function resetAll()
    bossStop()
    unstuck()
end

local function buildFallbackGui()
    -- Wizard GUI: small, blue, draggable. click a game = auto start + auto complete
    local UIS = game:GetService("UserInputService")
    local FULL_H = 360

    local C = {
        bg     = Color3.fromRGB(12, 18, 42),
        panel  = Color3.fromRGB(22, 34, 76),
        accent = Color3.fromRGB(80, 140, 255),
        glow   = Color3.fromRGB(140, 190, 255),
        text   = Color3.fromRGB(215, 228, 255),
        dim    = Color3.fromRGB(120, 140, 190),
        off    = Color3.fromRGB(40, 54, 100),
        row    = Color3.fromRGB(28, 42, 92),
    }

    local function new(class, props, parent)
        local o = Instance.new(class)
        for k, v in pairs(props) do o[k] = v end
        if parent then o.Parent = parent end
        return o
    end
    local function round(o, r) new("UICorner", {CornerRadius = UDim.new(0, r or 8)}, o) end

    local function guiParent()
        local ok, h = pcall(function() return gethui and gethui() end)
        if ok and h then return h end
        local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
        if ok2 and cg then return cg end
        return LP:WaitForChild("PlayerGui")
    end

    pcall(function()
        local old = guiParent():FindFirstChild("MimicGui")
        if old then old:Destroy() end
    end)

    local gui  = new("ScreenGui", {Name = "MimicGui", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, guiParent())
    local main = new("Frame", {Size = UDim2.fromOffset(250, FULL_H), Position = UDim2.new(0.5, -125, 0.5, -FULL_H / 2), BackgroundColor3 = C.bg, BorderSizePixel = 0, ClipsDescendants = true}, gui)
    round(main, 12)
    new("UIStroke", {Color = C.accent, Thickness = 1.5, Transparency = 0.2}, main)
    new("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(20, 30, 70), Color3.fromRGB(8, 12, 30))}, main)

    -- title bar (drag handle)
    local title = new("Frame", {Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = C.panel, BorderSizePixel = 0}, main)
    round(title, 12)
    new("TextLabel", {Size = UDim2.new(1, -70, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1, Text = "✦ Mimic", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.glow, TextXAlignment = Enum.TextXAlignment.Left}, title)

    local function titleBtn(txt, x)
        local b = new("TextButton", {Size = UDim2.fromOffset(22, 22), Position = UDim2.new(1, x, 0, 5), BackgroundColor3 = C.off, Text = txt, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.text, AutoButtonColor = true}, title)
        round(b, 6)
        return b
    end
    local minBtn   = titleBtn("-", -52)
    local closeBtn = titleBtn("x", -26)

    do
        local dragging, ds, sp
        title.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                dragging, ds, sp = true, i.Position, main.Position
                i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then dragging = false end end)
            end
        end)
        UIS.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                local d = i.Position - ds
                main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
            end
        end)
    end

    -- body
    local body = new("Frame", {Size = UDim2.new(1, 0, 1, -32), Position = UDim2.fromOffset(0, 32), BackgroundTransparency = 1}, main)

    local scope = "s1"
    local tabs, rows = {}, {}
    local function tabBtn(txt, x, key)
        local b = new("TextButton", {Size = UDim2.new(0.5, -14, 0, 26), Position = UDim2.new(x, x == 0 and 10 or 4, 0, 8), BackgroundColor3 = C.off, Text = txt, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.text, AutoButtonColor = false}, body)
        round(b, 7)
        tabs[key] = b
        return b
    end
    local tab1 = tabBtn("Section 1", 0, "s1")
    local tab2 = tabBtn("Tent", 0.5, "s2")

    local list = new("ScrollingFrame", {Size = UDim2.new(1, -20, 0, 176), Position = UDim2.fromOffset(10, 42), BackgroundColor3 = C.panel, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.accent, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y}, body)
    round(list, 8)
    new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, list)
    new("UIPadding", {PaddingTop = UDim.new(0, 5), PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5)}, list)

    -- one click on a game = start it (auto prompt + auto complete). click again = stop it.
    local busy = false
    local function clearTicks() for k in pairs(ticks) do ticks[k] = false end end
    local function startOne(name)
        local l = loops[name]
        if l and l.Running and not busy then
            stopLoop(name); floatOff()
            return
        end
        busy = false
        clearTicks()
        for n in pairs(loops) do stopLoop(n) end
        startLoop(name, function(ctl) runOne(name, ctl); floatOff() end)
    end

    local function refresh()
        for _, c in ipairs(list:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        table.clear(rows)
        for key, b in pairs(tabs) do
            b.BackgroundColor3 = (key == scope) and C.accent or C.off
        end
        local order  = scope == "s1" and ORDER_S1 or ORDER_S2
        local labels = scope == "s1" and LABEL_S1 or LABEL_S2
        for idx, name in ipairs(order) do
            local row = new("TextButton", {LayoutOrder = idx, Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = C.row, Text = "", AutoButtonColor = true}, list)
            round(row, 6)
            new("TextLabel", {Size = UDim2.new(1, -70, 1, 0), Position = UDim2.fromOffset(10, 0), BackgroundTransparency = 1, Text = labels[name] or name, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left}, row)
            local stat = new("TextLabel", {Size = UDim2.fromOffset(60, 26), Position = UDim2.new(1, -66, 0, 0), BackgroundTransparency = 1, Text = "▶ play", Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = C.glow, TextXAlignment = Enum.TextXAlignment.Right}, row)
            rows[name] = {btn = row, stat = stat}
            row.MouseButton1Click:Connect(function() startOne(name) end)
        end
    end
    tab1.MouseButton1Click:Connect(function() scope = "s1"; refresh() end)
    tab2.MouseButton1Click:Connect(function() scope = "s2"; refresh() end)

    -- live status: blue + "running" while a game is being played
    task.spawn(function()
        while gui.Parent do
            for name, r in pairs(rows) do
                local on = loops[name] ~= nil and loops[name].Running
                r.btn.BackgroundColor3 = on and C.accent or C.row
                r.stat.Text = on and "● running" or (notes[name] or "▶ play")
                r.stat.TextColor3 = on and Color3.new(1, 1, 1) or C.glow
            end
            task.wait(0.3)
        end
    end)

    local function btn(txt, x, w, y, h, col)
        local b = new("TextButton", {Size = UDim2.new(w, x == 0 and -14 or -14, 0, h), Position = UDim2.new(x, x == 0 and 10 or 4, 0, y), BackgroundColor3 = col or C.accent, Text = txt, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.new(1, 1, 1)}, body)
        round(b, 8)
        return b
    end

    local runAll  = btn("Play All", 0, 0.5, 226, 28)
    local stopBtn = btn("Stop All", 0.5, 0.5, 226, 28, Color3.fromRGB(60, 80, 150))
    runAll.MouseButton1Click:Connect(function()
        if busy then return end
        busy = true
        local s = scope
        for n in pairs(loops) do stopLoop(n) end
        clearTicks()
        for _, n in ipairs(s == "s1" and ORDER_S1 or ORDER_S2) do ticks[n] = true end
        task.spawn(function() runSelected(s); busy = false end)
    end)

    local bossBtn = btn("Boss Farm: OFF", 0, 1, 260, 28, C.off)
    bossBtn.Size = UDim2.new(1, -20, 0, 28)
    local function bossUI()
        bossBtn.Text = "Boss Farm: " .. (boss.Running and "ON" or "OFF")
        bossBtn.BackgroundColor3 = boss.Running and C.accent or C.off
    end
    bossBtn.MouseButton1Click:Connect(function()
        if boss.Running then bossStop() else bossStart() end
        bossUI()
    end)
    stopBtn.MouseButton1Click:Connect(function() resetAll(); busy = false; bossUI() end)

    local dcBtn = btn("Discord (copy link)", 0, 1, 294, 22, C.panel)
    dcBtn.Size = UDim2.new(1, -20, 0, 22)
    dcBtn.TextColor3 = C.glow
    dcBtn.TextSize = 11
    dcBtn.MouseButton1Click:Connect(function()
        if setclipboard then pcall(setclipboard, DISCORD_INVITE) end
        dcBtn.Text = "Copied!"
        task.delay(1.2, function() dcBtn.Text = "Discord (copy link)" end)
    end)

    new("TextLabel", {Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -16), BackgroundTransparency = 1, Text = "by " .. CREDIT_NAME, Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = C.dim}, body)

    -- minimize / close
    local mini = false
    minBtn.MouseButton1Click:Connect(function()
        mini = not mini
        body.Visible = not mini
        main.Size = mini and UDim2.fromOffset(250, 32) or UDim2.fromOffset(250, FULL_H)
    end)
    closeBtn.MouseButton1Click:Connect(function() resetAll(); gui:Destroy() end)

    refresh()
end

-- Wizard UI library (title: Mimic). falls back to the built-in GUI above if the library can't load.
local function stopEverything()
    for n in pairs(loops) do stopLoop(n) end
    for k in pairs(ticks) do ticks[k] = false end
    floatOff()
end
local function stopAndUnstuck(force) task.spawn(function() unstuck(force) end) end
local function playOne(name)
    task.spawn(function()
        if gameActive then unstuck(false) else stopEverything() end  -- leave the previous game first
        startLoop(name, function(ctl) runOne(name, ctl) end)
    end)
end
local function playAll(scopeKey)
    task.spawn(function()
        if gameActive then unstuck(false) else stopEverything() end
        for _, n in ipairs(scopeKey == "s1" and ORDER_S1 or ORDER_S2) do ticks[n] = true end
        runSelected(scopeKey)
    end)
end

local okLib, Library = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/reallycoolusername101-cmyk/Nil_Library/refs/heads/main/wizard"))()
end)

local builtWizard = false
if okLib and Library then
    local okW, errW = pcall(function()
        local Window = Library:NewWindow("Mimic")

        local S1 = Window:NewSection("Section 1")
        for _, name in ipairs(ORDER_S1) do
            S1:CreateButton(LABEL_S1[name] or name, function() playOne(name) end)
        end

        local S2 = Window:NewSection("Tent")
        for _, name in ipairs(ORDER_S2) do
            S2:CreateButton(LABEL_S2[name] or name, function() playOne(name) end)
        end

        local Misc = Window:NewSection("Misc")
        Misc:CreateButton("Play All Section 1", function() playAll("s1") end)
        Misc:CreateButton("Play All Tent", function() playAll("s2") end)
        Misc:CreateButton("Stop All", function() stopAndUnstuck(false) end)
        Misc:CreateButton("Unstuck (leave game)", function() stopAndUnstuck(true) end)
        Misc:CreateToggle("Boss Farm", function(state)
            if state then bossStart() else bossStop() end
        end)

        local Credit = Window:NewSection("Credit:" .. CREDIT_NAME)
        Credit:CreateButton("Discord Server", function()
            if setclipboard then pcall(setclipboard, DISCORD_INVITE) end
        end)
    end)
    builtWizard = okW
    if not okW then warn("[Mimic] wizard UI error: " .. tostring(errW)) end
else
    warn("[Mimic] wizard library failed to load: " .. tostring(Library))
end

if not builtWizard then
    buildFallbackGui()  -- built-in blue GUI
end
