//
//  Persistence.swift
//  Tari
//
//  Created by wjb on 2025/12/20.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        // 这里的名字必须和你的 .xcdatamodeld 文件名一致
        container = NSPersistentContainer(name: "TariModel")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                print("CoreData Error: \(error), \(error.userInfo)")
            }
        })
        
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
    
    func save() throws {
        let context = container.viewContext
        if context.hasChanges {
            try context.save()
        }
    }
}
