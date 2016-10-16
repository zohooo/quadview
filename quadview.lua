
require("wx")

VERSION = "0.3"

-----------------------------------------------------------
-- Generate a unique new wxWindowID
-----------------------------------------------------------

local COUNTER = wx.wxID_HIGHEST + 1

local function NewID()
    COUNTER = COUNTER + 1
    return COUNTER
end

ID = { }

-----------------------------------------------------------
-- Create main frame and bitmap controls
-----------------------------------------------------------

sep = package.config:sub(1,1) -- path separator

mainpath = wx.wxGetCwd()
datapath = os.getenv("APPDATA") .. sep .. "QuadView"
cfgname = datapath .. sep .. "quadview.ini"
runname = datapath .. sep .. "running"

if not wx.wxFileName.DirExists(datapath) and not wx.wxFileName.Mkdir(datapath) then
    wx.wxMessageBox("Failed to create main folder!", "Error")
    return
end

if not wx.wxFileName.FileExists(cfgname) then
    wx.wxMessageBox("Make sure you have installed preview package\n"
        .. "into your miktex or texlive distribution!", "Requirement")
end

local file = wx.wxFile()
file:Create(runname, true)
file:Close()

frame = wx.wxFrame(wx.NULL, wx.wxID_ANY, "QuadView" .. " " .. VERSION, wx.wxPoint(656,132),
                   wx.wxSize(350, 250), wx.wxDEFAULT_FRAME_STYLE+wx.wxSTAY_ON_TOP)

image = wx.wxImage()
bitmap = wx.wxBitmap()
preview = wx.wxStaticBitmap(frame, wx.wxID_ANY)

frame:Connect(wx.wxEVT_CLOSE_WINDOW, function(event)
    image:delete()
    bitmap:delete()
    if not wx.wxRemoveFile(runname) then
        wx.wxMessageBox("Unable to delete file!", "Error", wx.wxOK + wx.wxCENTRE, frame)
    end
    SavePosition()
    SaveEngine()
    event:Skip()
end)

-----------------------------------------------------------
-- Save and restore configurations
-----------------------------------------------------------

function GetConfig()
    local config = wx.wxFileConfig("QuadView", "", cfgname)
    if config then
        config:SetRecordDefaults()
    else
        print("Failed to load config file!")
    end
    return config
end

function SavePosition()
    local config = GetConfig()
    if not config then return end

    config:SetPath("/MainFrame")

    local s    = 0
    local w, h = frame:GetSizeWH()
    local x, y = frame:GetPositionXY()

    if frame:IsMaximized() then
        s = 1
    elseif frame:IsIconized() then
        s = 2
    end

    config:Write("s", s)

    if s == 0 then
        config:Write("x", x)
        config:Write("y", y)
        config:Write("w", w)
        config:Write("h", h)
    end

    config:delete() -- always delete the config
end

function RestorePosition()
    local config = GetConfig()
    if not config then return end

    config:SetPath("/MainFrame")

    local _, s = config:Read("s", -1)
    local _, x = config:Read("x", 0)
    local _, y = config:Read("y", 0)
    local _, w = config:Read("w", 0)
    local _, h = config:Read("h", 0)

    if (s ~= -1) and (s ~= 1) and (s ~= 2) then
        local clientX, clientY, clientWidth, clientHeight
        clientX, clientY, clientWidth, clientHeight = wx.wxClientDisplayRect()

        if x < clientX then x = clientX end
        if y < clientY then y = clientY end

        if w > clientWidth  then w = clientWidth end
        if h > clientHeight then h = clientHeight end

        frame:SetSize(x, y, w, h)
    elseif s == 1 then
        frame:Maximize(true)
    end

    config:delete() -- always delete the config
end

RestorePosition()

function SaveEngine()
    local config = GetConfig()
    if not config then return end

    config:SetPath("/Engine")
    config:Write("program", program)

    config:delete() -- always delete the config
end

function RestoreEngine()
    local config = GetConfig()
    if not config then return end

    config:SetPath("/Engine")
    _, program = config:Read("program", "xelatex")

    config:delete() -- always delete the config
end

RestoreEngine()

-----------------------------------------------------------
-- Resize the preview image
-----------------------------------------------------------

function ResizeControl()
    local size = frame:GetSize()
    local w, h = size:GetWidth(), size:GetHeight()
    size = frame:GetClientSize()
    local cw, ch = size:GetWidth(), size:GetHeight()
    local iw, ih = image:GetWidth(), image:GetHeight()
    if iw == 0 then iw = 320 end
    if ih == 0 then ih = 240 end
    local nh =  cw * ih / iw
    bitmap = wx.wxBitmap(image:Scale(cw, nh, wx.wxIMAGE_QUALITY_HIGH))
    preview:SetBitmap(bitmap)
    preview:SetSize(0, 0, cw, ch)
    if nh - ch > 2 or ch - nh > 2 then
        frame:SetSize(w, h + nh - ch)
    end
    frame:Refresh()
end

frame:Connect(wx.wxEVT_SIZE, function(event)
    ResizeControl()
    event:Skip()
end)

-----------------------------------------------------------
-- Execute commands asynchronously
-----------------------------------------------------------

local proc, streamIn, streamErr, streamOut
local inRunning = false

ID.TIMER_EXECUTION = NewID()
local execTimer = wx.wxTimer(frame, ID.TIMER_EXECUTION)

function ReadStream()
    if streamIn and streamIn:CanRead() then
        local str = streamIn:Read(4096)
        --print(str)
    end
    if streamErr and streamErr:CanRead() then
        local str = streamErr:Read(4096)
        --print(str)
    end
end

function ExecCommand(cmd, dir, callback)
    if isRunning then
        print("isRunning")
        return true
    else
        print("notRunning")
    end

    proc = wx.wxProcess()
    proc:Redirect()
    proc:Connect(wx.wxEVT_END_PROCESS, function(event)
        execTimer:Stop();
        ReadStream()
        proc = nil
        isRunning = false
        callback()
    end)

    local cwd = wx.wxGetCwd()
    wx.wxSetWorkingDirectory(dir)
    print(cmd)
    isRunning = true
    local pid = wx.wxExecute(cmd, wx.wxEXEC_ASYNC, proc)
    wx.wxSetWorkingDirectory(cwd)

    if pid == -1 then
        print("Unknown ERROR in running program!\n")
    else
        streamIn = proc and proc:GetInputStream()
        streamErr = proc and proc:GetErrorStream()
        streamOut = proc and proc:GetOutputStream()
        execTimer:Start(200);
    end

    return false
end

frame:Connect(ID.TIMER_EXECUTION, wx.wxEVT_TIMER, ReadStream)

-----------------------------------------------------------
-- Use a timer to update preview image
-----------------------------------------------------------

ID.TIMER_PREVIEW = NewID()
local previewTimer = wx.wxTimer(frame, ID.TIMER_PREVIEW)

dirname = datapath .. sep .. "directory.txt"
texname = datapath .. sep .. "fragment.tex"
pdfname = datapath .. sep .. "fragment.pdf"
pngname = datapath .. sep .. "fragment.png"

if not program then program = "xelatex" end
switch = "-interaction=nonstopmode -output-directory=\"" .. datapath .. "\""

local isPending = false
modtime = wx.wxDateTime()

function CheckFileTime()
    local fn = wx.wxFileName(texname)
    if not fn:FileExists() then return false end
    local time = fn:GetModificationTime()
    if time:IsLaterThan(modtime) then
        modtime = time
        return true
    else
        return false
    end
end

function CompileDocument()
    local fn = wx.wxFileName(dirname)
    if not fn:FileExists() then return end
    local file = io.input(dirname)
    local dir = io.read("*line")
    io.close(file)
    if not CheckFileTime() and not isPending then
        --print(modtime:GetTicks())
        return
    end
    local cmd = program .. " " .. switch .. " \"" .. texname .. "\""
    isPending = ExecCommand(cmd, dir, PreviewDocument)
end

function PreviewDocument()
    local cmd = "mudraw -r 300 -o " .. pngname .. " " .. pdfname .. " 1"
    ExecCommand(cmd, mainpath, UpdateBitmap)
end

function UpdateBitmap()
    if (image:LoadFile(pngname, wx.wxBITMAP_TYPE_PNG)) then
        ResizeControl()
    else
        --wx.wxMessageBox("Unable to load image!", "Error", wx.wxOK + wx.wxCENTRE, frame)
    end
end

frame:Connect(ID.TIMER_PREVIEW, wx.wxEVT_TIMER, CompileDocument)

previewTimer:Start(1000);

-----------------------------------------------------------
-- The popup menu
-----------------------------------------------------------

menu = wx.wxMenu()

ID.ENGINE   = NewID()
ID.PDFLATEX = NewID()
ID.XELATEX  = NewID()
ID.LUALATEX = NewID()

menu:Append(ID.ENGINE, "Engine", wx.wxMenu{
    { ID.PDFLATEX, "&PDFLaTeX", "Use PDFLaTeX", wx.wxITEM_RADIO },
    { ID.XELATEX,  "&XeLaTeX",  "Use XeLaTeX",  wx.wxITEM_RADIO },
    { ID.LUALATEX, "&LuaLaTeX", "Use LuaLaTeX", wx.wxITEM_RADIO },
})

menu:Check(ID[string.upper(program)], true)

menu:AppendSeparator()

ID.FRAGMENT = NewID()

menu:Append(ID.FRAGMENT, "&Fragment", "Open Fragment Folder")

menu:AppendSeparator()

ID.ABOUT = NewID()

menu:Append(ID.ABOUT, "&About", "About QuadView")

frame:Connect(ID.PDFLATEX, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    program = "pdflatex"
end)

frame:Connect(ID.XELATEX, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    program = "xelatex"
end)

frame:Connect(ID.LUALATEX, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    program = "lualatex"
end)

frame:Connect(ID.FRAGMENT, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    wx.wxExecute("explorer "  .. datapath, wx.wxEXEC_ASYNC)
end)

frame:Connect(ID.ABOUT, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    wx.wxMessageBox("QuadView" .. " " .. VERSION, "ABOUT")
end)

frame:Connect(wx.wxEVT_CONTEXT_MENU, function(event)
    frame:PopupMenu(menu)
end)

-----------------------------------------------------------
-- Show main frame and start event loop
-----------------------------------------------------------

frame:Show(true)

wx.wxGetApp():MainLoop()