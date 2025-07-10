//
//  MCPController.swift
//  FlowDown
//
//  Created by LiBr on 6/30/25.
//
import Combine
import ConfigurableKit
import Storage
import UIKit

extension SettingController.SettingContent {
    class MCPController: UIViewController {
        let tableView: UITableView
        let dataSource: DataSource

        enum TableViewSection: String {
            case main
        }

        typealias DataSource = UITableViewDiffableDataSource<TableViewSection, ModelContextServer.ID>
        typealias Snapshot = NSDiffableDataSourceSnapshot<TableViewSection, ModelContextServer.ID>

        var cancellable: Set<AnyCancellable> = []

        init() {
            tableView = UITableView(frame: .zero, style: .plain)
            dataSource = .init(tableView: tableView, cellProvider: Self.cellProvider)

            super.init(nibName: nil, bundle: nil)
            title = String(localized: "MCP Servers")

            tableView.register(
                MCPServerCell.self,
                forCellReuseIdentifier: NSStringFromClass(MCPServerCell.self)
            )
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            cancellable.forEach { $0.cancel() }
            cancellable.removeAll()
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .background

            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .add,
                target: self,
                action: #selector(addClientTapped)
            )

            dataSource.defaultRowAnimation = .fade
            tableView.delegate = self
            tableView.separatorStyle = .singleLine
            tableView.separatorColor = SeparatorView.color
            tableView.backgroundColor = .clear
            tableView.backgroundView = nil
            tableView.alwaysBounceVertical = true
            tableView.contentInset = .zero
            tableView.scrollIndicatorInsets = .zero
            view.addSubview(tableView)
            tableView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }

            MCPService.shared.servers
                .ensureMainThread()
                .sink { [weak self] clients in
                    self?.updateSnapshot(clients)
                }
                .store(in: &cancellable)
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            MCPService.shared.updateFromDatabase()
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }

        func updateSnapshot(_ clients: [ModelContextServer]) {
            var snapshot = Snapshot()
            snapshot.appendSections([.main])
            snapshot.appendItems(clients.map(\.id), toSection: .main)
            dataSource.apply(snapshot, animatingDifferences: true)
        }

        static let cellProvider: DataSource.CellProvider = { tableView, indexPath, clientId in
            let cell = tableView.dequeueReusableCell(
                withIdentifier: NSStringFromClass(MCPServerCell.self),
                for: indexPath
            )
            cell.contentView.isUserInteractionEnabled = false
            if let cell = cell as? MCPServerCell {
                cell.configure(with: clientId)
            }
            return cell
        }
    }
}

extension SettingController.SettingContent.MCPController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let clientId = dataSource.itemIdentifier(for: indexPath) else { return }
        let controller = MCPEditorController(clientId: clientId)
        navigationController?.pushViewController(controller, animated: true)
    }

    func tableView(_: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let clientId = dataSource.itemIdentifier(for: indexPath) else { return nil }
        let delete = UIContextualAction(
            style: .destructive,
            title: String(localized: "Delete")
        ) { _, _, completion in
            MCPService.shared.remove(clientId)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
