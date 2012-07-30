require 'spec_helper'

describe CarrierWave::Video do
  class Video; end

  class TestVideoUploader
    include CarrierWave::Video
    def cached?; end
    def cache_stored_file!; end
    def model
      @video ||= Video.new
    end
  end

  let(:converter) { TestVideoUploader.new }

  describe ".encode_video" do
    it "processes the model" do
      TestVideoUploader.should_receive(:process).with(encode_video: ["format", :opts])
      TestVideoUploader.encode_video("format", :opts)
    end

    it "does not require options" do
      TestVideoUploader.should_receive(:process).with(encode_video: ["format", {}])
      TestVideoUploader.encode_video("format")
    end
  end

  describe ".encode_ogv" do
    it "processes the model" do
      TestVideoUploader.should_receive(:process).with(encode_ogv: [:opts])
      TestVideoUploader.encode_ogv(:opts)
    end

    it "does not require options" do
      TestVideoUploader.should_receive(:process).with(encode_ogv: [{}])
      TestVideoUploader.encode_ogv
    end
  end

  describe "#encode_video" do
    let(:format) { 'webm' }
    let(:movie) { mock }

    before do
      converter.stub(:current_path).and_return('video/path/file.mov')

      FFMPEG::Movie.should_receive(:new).and_return(movie)
    end

    context "with no options set" do
      before {  File.should_receive(:rename) }

      it "calls transcode with correct format options" do
        movie.should_receive(:transcode) do |path, opts, codec_opts|
          codec_opts.should == {preserve_aspect_ratio: :width}

          opts[:video_codec].should == 'libvpx'
          opts[:audio_codec].should == 'libvorbis'
          opts[:custom].should == '-b 1500k -ab 160000 -f webm -g 30 '

          path.should == "video/path/tmpfile.#{format}"
        end

        converter.encode_video(format)
      end

      it "provides a default for the resolution" do
        movie.should_receive(:transcode) do |path, opts, codec_opts|
          opts[:resolution].should == '640x360'
        end

        converter.encode_video(format)
      end
    end

    context "with callbacks set" do
      before { movie.should_receive(:transcode) }
      let(:opts) do
        { callbacks: {
             before_transcode: :method1,
             after_transcode: :method2,
             rescue: :method3,
             ensure: :method4
          }
        }
      end

      context "no exceptions raised" do
        before {  File.should_receive(:rename) }

        it "calls before_transcode, after_transcode, and ensure" do
          converter.model.should_receive(:method1).with(format, opts).ordered
          converter.model.should_receive(:method2).with(format, opts).ordered
          converter.model.should_not_receive(:method3)
          converter.model.should_receive(:method4).with(format, opts).ordered

          converter.encode_video(format, opts)
        end
      end

      context "exception raised" do
        let(:e) { StandardError.new("test error") }
        before { File.should_receive(:rename).and_raise(e) }


        it "calls before_transcode and ensure" do
          converter.model.should_receive(:method1).with(format, opts).ordered
          converter.model.should_not_receive(:method2)
          converter.model.should_receive(:method3).with(format, opts).ordered
          converter.model.should_receive(:method4).with(format, opts).ordered

          lambda do
            converter.encode_video(format, opts)
          end.should raise_exception(CarrierWave::ProcessingError)
        end
      end
    end

    context "with logger set" do
      let(:logger) { mock }
      before do
        converter.model.stub(:logger).and_return(logger)
        movie.should_receive(:transcode)
      end

      context "with no exceptions" do
        before { File.should_receive(:rename) }

        it "sets FFMPEG logger to logger and resets" do
          old_logger = ::FFMPEG.logger
          ::FFMPEG.should_receive(:logger=).with(logger).ordered
          ::FFMPEG.should_receive(:logger=).with(old_logger).ordered
          converter.encode_video(format, logger: :logger)
        end
      end

      context "with exceptions" do
        let(:e) { StandardError.new("test error") }
        before { File.should_receive(:rename).and_raise(e) }

        it "logs exception" do
          logger.should_receive(:error).with("#{e.class}: #{e.message}")
          logger.should_receive(:error).any_number_of_times #backtrace

          lambda do
            converter.encode_video(format, logger: :logger)
          end.should raise_exception(CarrierWave::ProcessingError)
        end
      end
    end

    context "with watermark set" do
      before { File.should_receive(:rename) }

      it "appends watermark params to custom params for ffmpeg" do
        movie.should_receive(:transcode) do |path, opts, codec_opts|
          codec_opts.should == {preserve_aspect_ratio: :width}

          opts[:video_codec].should == 'libvpx'
          opts[:audio_codec].should == 'libvorbis'
          opts[:custom].should == "-b 1500k -ab 160000 -f webm -g 30 -vf \"movie=path/to/file.png [logo]; [in][logo] overlay=5:main_h-overlay_h-5 [out]\""

          path.should == "video/path/tmpfile.#{format}"
        end

        converter.encode_video(format, watermark: {
          path: 'path/to/file.png',
          position: :bottom_left,
          pixels_from_edge: 5
        })
      end

      it "only requires path watermark parameter" do
        movie.should_receive(:transcode) do |path, opts, codec_opts|
          codec_opts.should == {preserve_aspect_ratio: :width}

          opts[:video_codec].should == 'libvpx'
          opts[:audio_codec].should == 'libvorbis'
          opts[:custom].should == "-b 1500k -ab 160000 -f webm -g 30 -vf \"movie=path/to/file.png [logo]; [in][logo] overlay= [out]\""

          path.should == "video/path/tmpfile.#{format}"
        end

        converter.encode_video(format, watermark: {
          path: 'path/to/file.png'
        })
      end
    end

    context "with resolution set to :same" do
      before do
        File.should_receive(:rename)
        movie.stub(:resolution).and_return('1280x720')
      end

      it "sets the output resolution to match that of the input" do
        movie.should_receive(:transcode) do |path, opts, codec_opts|
          opts[:resolution].should == '1280x720'
        end

        converter.encode_video(format, resolution: :same)
      end
    end

    context "with custom passed in" do
      before do
        File.should_receive(:rename)
      end

      it "takes the provided custom param" do
        movie.should_receive(:transcode) do |path, opts, codec_opts|
          opts[:custom].should == '-preset slow' # a la changes in ffmpeg 0.11.1
        end

        converter.encode_video(format, custom: '-preset slow')
      end

      it "maintains the watermark params" do
        movie.should_receive(:transcode) do |path, opts, codec_opts|
          opts[:custom].should == "-preset slow -vf \"movie=path/to/file.png [logo]; [in][logo] overlay= [out]\""
        end

        converter.encode_video(format, custom: '-preset slow', watermark: {
          path: 'path/to/file.png'
        })
      end
    end
  end


  describe "#encode_ogv" do
    let(:movie) { mock }
    let(:output_path) { 'video/path/tmpfile.ogv' }
    let(:movie_path) { 'video/path/input.mov' }
    let(:logger) { mock(:logger) }


    before do
      converter.model.stub(:logger).and_return(logger)
      File.should_receive(:rename)
      converter.stub(:current_path).and_return('video/path/input.mov')
    end

    context "no options set" do
      it "calls transcode with correct format options" do
        transcoder = mock(:transcoder)
        CarrierWave::Video::FfmpegTheora.should_receive(:new).with(movie_path, output_path).and_return(transcoder)
        transcoder.should_receive(:run)

        converter.encode_ogv({})
      end
    end

    context "with logger set" do
      before do
        converter.model.stub(:logger).and_return(logger)
      end

      it "calls transcode with correct format options and passes logger to transcoder" do
        transcoder = mock(:transcoder)
        CarrierWave::Video::FfmpegTheora.should_receive(:new).with(movie_path, output_path).and_return(transcoder)
        transcoder.should_receive(:run).with(logger)

        converter.encode_ogv({logger: :logger})
      end
    end
  end

end
