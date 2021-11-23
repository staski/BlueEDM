//
//  EdmFileList.swift
//  BlueEDM
//
//  Created by Staszkiewicz, Carl Philipp on 11.10.21.
//

import SwiftUI

struct EdmFile : Identifiable {
    var id: Date { createdAt }
    
    let fileURL: URL
    let createdAt: Date
}

struct EdmFileRow: View {
    
    var fileURL: URL
    
    var body: some View {
        HStack {
            Text("\(fileURL.lastPathComponent)")
            Spacer()
        }
    }
}

struct EdmFileList: View {
    @EnvironmentObject var edm : EDMBluetoothManager
    
 
    var body: some View {
        List {
              ForEach(edm.edmFiles, id: \.createdAt) { file in
                  EdmFileRow(fileURL: file.fileURL)
              }
          }
    }   
}

struct EdmFileList_Previews: PreviewProvider {
    static var previews: some View {
        EdmFileList()
    }
}
