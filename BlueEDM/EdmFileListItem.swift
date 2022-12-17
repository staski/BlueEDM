//
//  SwiftUIView.swift
//  BlueEDM
//
//  Created by Staszkiewicz, Carl Philipp on 09.12.22.
//

import SwiftUI

struct EdmFileListItem: View {
    let name : String
    let value : String
    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Text(value)
        }
    }
}


