/*
 *  Copyright (c) 2016 Spotify AB.
 *
 *  Licensed to the Apache Software Foundation (ASF) under one
 *  or more contributor license agreements.  See the NOTICE file
 *  distributed with this work for additional information
 *  regarding copyright ownership.  The ASF licenses this file
 *  to you under the Apache License, Version 2.0 (the
 *  "License"); you may not use this file except in compliance
 *  with the License.  You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing,
 *  software distributed under the License is distributed on an
 *  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 *  KIND, either express or implied.  See the License for the
 *  specific language governing permissions and limitations
 *  under the License.
 */

import Foundation
import HubFramework

/// Content operation factory used for the "Root" feature
class RootContentOperationFactory: NSObject, HUBContentOperationFactory {
    func createContentOperations(forViewURI viewURI: URL) -> [HUBContentOperation] {
        //  return [RootContentOperation()]
        
       
        let headerOp :HUBBlockContentOperation =  HUBBlockContentOperation { (operationContext: HUBContentOperationContext) in
            
            let viewModelBuilder = operationContext.viewModelBuilder
            let headerBuilder = viewModelBuilder.headerComponentModelBuilder
            headerBuilder.componentName = DefaultComponentNames.header
            headerBuilder.title = "A sticky header!"
            headerBuilder.backgroundImageURL = URL(string: "https://spotify.github.io/HubFramework/resources/getting-started-gothenburg.jpg")
        }
        
        let staticOp :HUBBlockContentOperation =  HUBBlockContentOperation { (operationContext: HUBContentOperationContext) in
            
            let viewModelBuilder = operationContext.viewModelBuilder
            
            let startIndex = 1
            let endIndex = 2
            
            (startIndex...endIndex).forEach { index in
                let rowBuilder = viewModelBuilder.builderForBodyComponentModel(withIdentifier: "row-\(index)")
                rowBuilder.title = "Static Row number \(index)"
            }
            
        }

        
        
        return [headerOp, DynamicRootContentOperation(),GitHubSearchActivityIndicatorContentOperation(), staticOp]
    }
}
