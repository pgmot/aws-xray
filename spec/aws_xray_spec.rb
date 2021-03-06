require 'spec_helper'
require 'timeout'

RSpec.describe Aws::Xray do
  before do
    allow(Aws::Xray.config).to receive(:client_options).and_return(client_options)
  end
  let(:client_options) { { sock: io } }
  let(:io) { Aws::Xray::TestSocket.new }

  describe '.trace' do
    context 'when succeed' do
      it 'starts tracing' do
        Aws::Xray.trace(name: 'test') {}
        expect(io.tap(&:rewind).read.split("\n").size).to eq(2)
      end
    end

    context 'when the name is missing' do
      around do |ex|
        back, Aws::Xray.config.name = Aws::Xray.config.name, nil
        ex.run
        Aws::Xray.config.name = back
      end

      it 'raises MissingNameError' do
        expect { Aws::Xray.trace {} }.to raise_error(Aws::Xray::MissingNameError)
      end
    end

    context 'when timeout error is raised' do
      it 'captures the error' do
        expect {
          Aws::Xray.trace(name: 'test') do
            Timeout.timeout(0.01) do
              sleep 0.03
            end
          end
        }.to raise_error(Timeout::Error)
        sent_jsons = io.tap(&:rewind).read.split("\n")
        expect(sent_jsons.size).to eq(2)

        body = JSON.parse(sent_jsons[1])
        expect(body['fault']).to eq(true)
      end
    end
  end

  describe '.started?' do
    context 'when tracing context is started' do
      it 'returns true' do
        Aws::Xray.trace do
          expect(Aws::Xray.started?).to eq(true)
        end
      end
    end

    context 'when tracing context is not started' do
      it 'returns false' do
        expect(Aws::Xray.started?).to eq(false)
      end
    end
  end

  describe '.current_context' do
    context 'when tracing context is started' do
      it 'returns current context' do
        Aws::Xray.trace do
          expect(Aws::Xray.current_context).to be_a(Aws::Xray::Context)
          expect { Aws::Xray.with_given_context(Aws::Xray.current_context.copy) { } }.not_to raise_error
        end
      end
    end

    context 'when tracing context is not started' do
      it 'raises Aws::Xray::NotSetError' do
        expect { Aws::Xray.current_context }.to raise_error(Aws::Xray::NotSetError)
      end
    end
  end

  describe '.start_subsegment' do
    context 'when tracing context is started' do
      it 'yields real subsegment' do
        Aws::Xray.trace do
          Aws::Xray.start_subsegment(name: 'a', remote: false) do |sub|
            expect(sub).to be_a(Aws::Xray::Subsegment)
            expect(sub.name).to eq('a')
          end
        end
      end
    end

    context 'when tracing context is not started' do
      it 'yields null subsegment' do
        Aws::Xray.start_subsegment(name: 'a', remote: false) do |sub|
          expect(sub).to be_a(Aws::Xray::Subsegment)
          expect(sub.name).not_to eq('a')
        end
      end
    end
  end

  describe '.disable_trace and .disabled?' do
    context 'when tracing context is started' do
      it 'disables specific tracing' do
        Aws::Xray.trace do
          Aws::Xray.disable_trace(:test) do
            expect(Aws::Xray.disabled?(:test)).to eq(true)
          end
        end
      end
    end

    context 'when tracing context is not started' do
      it 'calls given block' do
        expect { Aws::Xray.disable_trace(:test) { } }.not_to raise_error
        expect { Aws::Xray.disabled?(:test) { } }.not_to raise_error
      end
    end
  end

  describe '.overwrite' do
    context 'when the context is not set' do
      it 'calls given block' do
        expect { Aws::Xray.overwrite(name: 'overwrite') { } }.not_to raise_error

        sent_jsons = io.tap(&:rewind).read.split("\n")
        expect(sent_jsons.size).to eq(0)
      end
    end

    context 'when the context is set' do
      it 'overwrites name' do
        Aws::Xray.trace(name: 'test') do
          Aws::Xray.overwrite(name: 'overwrite') do
            Aws::Xray.start_subsegment(name: 'name1', remote: false) {}
          end
        end

        sent_jsons = io.tap(&:rewind).read.split("\n")
        expect(sent_jsons.size).to eq(4)
        overwrote_one = JSON.parse(sent_jsons[1])

        expect(overwrote_one['name']).to eq('overwrite')
      end
    end
  end
end
