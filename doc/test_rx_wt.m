clear;
close all;

bbrx = basebandReceiver("My USRP N310");

interpolator = 4;
masterclockrate = 122.88e6;
samplerate = masterclockrate/interpolator
bbrx.SampleRate = samplerate;
bbrx.CenterFrequency = 2.33e9;
bbrx.RadioGain = 50;
bbrx.DroppedSamplesAction = "warning";
bbrx.CaptureDataType = 'double';
bbrx
disp('-----start Capturing!-----')
start = tic;
for i = 1:100
    [data,timestamps,overflows] = capture(bbrx,38400);
end
endtime = toc(start);
disp('-----Capturing complete!-----')

