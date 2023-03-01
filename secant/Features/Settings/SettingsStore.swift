import ComposableArchitecture
import MessageUI
import SwiftUI

typealias SettingsStore = Store<SettingsReducer.State, SettingsReducer.Action>
typealias SettingsViewStore = ViewStore<SettingsReducer.State, SettingsReducer.Action>

struct SettingsReducer: ReducerProtocol {
    struct State: Equatable {
        enum Destination {
            case backupPhrase
        }

        @BindingState var alert: AlertState<SettingsReducer.Action>?
        var destination: Destination?
        var exportLogsDisabled = false
        @BindingState var isCrashReportingOn: Bool
        var isSharingLogs = false
        var phraseDisplayState: RecoveryPhraseDisplayReducer.State
        var rescanDialog: ConfirmationDialogState<SettingsReducer.Action>?
        var supportData: SupportData?

        var tempSDKDir: URL {
            let tempDir = FileManager.default.temporaryDirectory
            let sdkFileName = "sdkLogs.txt"
            return tempDir.appendingPathComponent(sdkFileName)
        }

        var tempTCADir: URL {
            let tempDir = FileManager.default.temporaryDirectory
            let sdkFileName = "tcaLogs.txt"
            return tempDir.appendingPathComponent(sdkFileName)
        }

        var tempWalletDir: URL {
            let tempDir = FileManager.default.temporaryDirectory
            let sdkFileName = "walletLogs.txt"
            return tempDir.appendingPathComponent(sdkFileName)
        }
    }

    enum Action: BindableAction, Equatable {
        case backupWallet
        case backupWalletAccessRequest
        case binding(BindingAction<SettingsReducer.State>)
        case cancelRescan
        case dismissAlert
        case exportLogs
        case fullRescan
        case logsExported
        case logsShareFinished
        case onAppear
        case phraseDisplay(RecoveryPhraseDisplayReducer.Action)
        case quickRescan
        case rescanBlockchain
        case sendSupportMail
        case sendSupportMailFinished
        case testCrashReporter // this will crash the app if live.
        case updateDestination(SettingsReducer.State.Destination?)
    }

    @Dependency(\.localAuthentication) var localAuthentication
    @Dependency(\.mnemonic) var mnemonic
    @Dependency(\.sdkSynchronizer) var sdkSynchronizer
    @Dependency(\.logsHandler) var logsHandler
    @Dependency(\.walletStorage) var walletStorage
    @Dependency(\.userStoredPreferences) var userStoredPreferences
    @Dependency(\.crashReporter) var crashReporter

    var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isCrashReportingOn = !userStoredPreferences.isUserOptedOutOfCrashReporting()
                return .none
            case .backupWalletAccessRequest:
                return .run { send in
                    if await localAuthentication.authenticate() {
                        await send(.backupWallet)
                    }
                }
                
            case .backupWallet:
                do {
                    let storedWallet = try walletStorage.exportWallet()
                    let phraseWords = try mnemonic.asWords(storedWallet.seedPhrase.value())
                    let recoveryPhrase = RecoveryPhrase(words: phraseWords.map { $0.redacted })
                    state.phraseDisplayState.phrase = recoveryPhrase
                    return EffectTask(value: .updateDestination(.backupPhrase))
                } catch {
                    // TODO: [#221] - merge with issue 221 (https://github.com/zcash/secant-ios-wallet/issues/221) and its Error States
                    return .none
                }

            case .binding(\.$isCrashReportingOn):
                if state.isCrashReportingOn {
                    crashReporter.optOut()
                } else {
                    crashReporter.optIn()
                }

                return .run { [state] _ in
                    await userStoredPreferences.setIsUserOptedOutOfCrashReporting(state.isCrashReportingOn)
                }
                
            case .cancelRescan, .quickRescan, .fullRescan:
                state.rescanDialog = nil
                return .none

            case .dismissAlert:
                state.alert = nil
                return .none
                
            case .exportLogs:
                state.exportLogsDisabled = true
                return .run { [state] send in
                    do {
                        try await logsHandler.exportAndStoreLogs(state.tempSDKDir, state.tempTCADir, state.tempWalletDir)
                        await send(.logsExported)
                    } catch {
                        // TODO: [#527] address the error here https://github.com/zcash/secant-ios-wallet/issues/527
                    }
                }
                
            case .logsExported:
                state.exportLogsDisabled = false
                state.isSharingLogs = true
                return .none

            case .logsShareFinished:
                state.isSharingLogs = false
                return .none

            case .rescanBlockchain:
                state.rescanDialog = .init(
                    title: TextState("Rescan"),
                    message: TextState("Select the rescan you want"),
                    buttons: [
                        .default(TextState("Quick rescan"), action: .send(.quickRescan)),
                        .default(TextState("Full rescan"), action: .send(.fullRescan)),
                        .cancel(TextState("Cancel"))
                    ]
                )
                return .none

            case .phraseDisplay:
                state.destination = nil
                return .none
                
            case .updateDestination(let destination):
                state.destination = destination
                return .none

            case .testCrashReporter:
                crashReporter.testCrash()
                return .none

            case .binding:
                return .none

            case .sendSupportMail:
                if MFMailComposeViewController.canSendMail() {
                    state.supportData = SupportDataGenerator.generate()
                } else {
                    state.alert = AlertState(
                        title: TextState("Can't send email"),
                        message: TextState("""
                        It looks like that you don't have any email account configured on your device. Therefore it's not possible to send a support \
                        email.
                        """),
                        dismissButton: .default(TextState("Ok"), action: .send(.sendSupportMailFinished))
                    )
                }

                return .none

            case .sendSupportMailFinished:
                state.supportData = nil
                return .none
            }
        }

        Scope(state: \.phraseDisplayState, action: /Action.phraseDisplay) {
            RecoveryPhraseDisplayReducer()
        }
    }
}

// MARK: - ViewStore

extension SettingsViewStore {
    var destinationBinding: Binding<SettingsReducer.State.Destination?> {
        self.binding(
            get: \.destination,
            send: SettingsReducer.Action.updateDestination
        )
    }
    
    var bindingForBackupPhrase: Binding<Bool> {
        self.destinationBinding.map(
            extract: { $0 == .backupPhrase },
            embed: { $0 ? .backupPhrase : nil }
        )
    }
}

// MARK: - Store

extension SettingsStore {
    func backupPhraseStore() -> RecoveryPhraseDisplayStore {
        self.scope(
            state: \.phraseDisplayState,
            action: SettingsReducer.Action.phraseDisplay
        )
    }
}

// MARK: Placeholders

extension SettingsReducer.State {
    static let placeholder = SettingsReducer.State(
        isCrashReportingOn: true,
        phraseDisplayState: RecoveryPhraseDisplayReducer.State(
            phrase: .placeholder
        )
    )
}

extension SettingsStore {
    static let placeholder = SettingsStore(
        initialState: .placeholder,
        reducer: SettingsReducer()
    )
}
