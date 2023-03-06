import SwiftUI
import ComposableArchitecture

struct CreateTransaction: View {
    let store: SendFlowStore

    var body: some View {
        UITextView.appearance().backgroundColor = .clear
        
        return WithViewStore(store) { viewStore in
            VStack {
                VStack(spacing: 0) {
                    Text("balance.available".localized("\(viewStore.shieldedBalance.data.total.decimalString())"))
                        .font(.system(size: 32))
                        .fontWeight(.bold)
                    Text("send.fundsInfo")
                        .font(.system(size: 16))
                }
                .foregroundColor(Asset.Colors.Mfp.fontDark.color)
                .padding()

                TransactionAddressTextField(
                    store: store.scope(
                        state: \.transactionAddressInputState,
                        action: SendFlowReducer.Action.transactionAddressInput
                    )
                )
                .padding()

                TransactionAmountTextField(
                    store: store.scope(
                        state: \.transactionAmountInputState,
                        action: SendFlowReducer.Action.transactionAmountInput
                    )
                )
                .padding()

                MultipleLineTextField(
                    store: store.memoStore(),
                    title: "send.memoPlaceholder",
                    titleAccessoryView: {}
                )
                .frame(height: 200)
                .padding()
                
                Button(
                    action: { viewStore.send(.sendPressed) },
                    label: { Text("general.send") }
                )
                .activeButtonStyle

                Spacer()
            }
            .navigationTitle("send.title")
            .navigationBarTitleDisplayMode(.inline)
            .padding()
            .applyScreenBackground()
        }
    }
}

// MARK: - Previews

struct Create_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            StateContainer(
                initialState: ( false )
            ) { _ in
                CreateTransaction(store: .placeholder)
            }
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.light)
        }
    }
}
