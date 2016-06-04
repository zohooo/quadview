
require("wx")

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

runname = datapath .. sep .. "running"

local file = wx.wxFile()
file:Create(runname, true)
file:Close()

frame = wx.wxFrame(wx.NULL, wx.wxID_ANY, "QuadView", wx.wxDefaultPosition,
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
    event:Skip()
end)

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
        return
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

program = "xelatex"
switch = "-interaction=nonstopmode -output-directory=\"" .. datapath .. "\""

function CompileDocument()
    local file = io.input(dirname)
    local dir = io.read("*line")
    io.close(file)
    local cmd = program .. " " .. switch .. " \"" .. texname .. "\""
    ExecCommand(cmd, dir, PreviewDocument)
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

previewTimer:Start(8000);

-----------------------------------------------------------
-- Show main frame and start event loop
-----------------------------------------------------------

frame:Show(true)

wx.wxGetApp():MainLoop()
